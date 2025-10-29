package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/expressions"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/orderings"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/repository"
	"github.com/redis/go-redis/v9"
)

const (
	PURPOSE = "key-authorization"
	LABEL   = "authorization-key"
)

type HSMServer struct {
	key      *SigningKey
	keysRepo repository.Repository[*Keys]
}

type SignRequest struct {
	Payload json.RawMessage `json:"payload"` // JSON payload to sign
}

type SignResponseBody struct {
	Payload json.RawMessage `json:"payload"` // JSON that was signed
	Hsm     SignHsm         `json:"hsm"`     // identity of the HSM key
}

type SignHsm struct {
	Identity     string `json:"identity"`
	GenerationId string `json:"generationId"`
}

type SignResponse struct {
	Body      SignResponseBody `json:"body"`      // The data that was signed (as JSON)
	Signature string           `json:"signature"` // CESR-encoded signature
}

type PublicKeyResponse struct {
	PublicKey string `json:"publicKey"` // CESR-encoded public key
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func NewHSMServer() (*HSMServer, error) {
	log.Printf("Starting HSM server initialization...")

	migrations := []string{
		KEYS_TABLE_SQL,
	}

	user := os.Getenv("POSTGRES_USER")
	password := os.Getenv("POSTGRES_PASSWORD")
	database := os.Getenv("POSTGRES_DATABASE")
	host := os.Getenv("POSTGRES_HOST")
	port := os.Getenv("POSTGRES_PORT")

	log.Printf("Connecting to PostgreSQL: host=%s port=%s database=%s user=%s", host, port, database, user)

	dsn := fmt.Sprintf(
		"user=%s password=%s dbname=%s host=%s port=%s sslmode=disable",
		user,
		password,
		database,
		host,
		port,
	)

	store, err := NewPostgreSQLStore(context.Background(), dsn, migrations)
	if err != nil {
		log.Printf("Failed to connect to PostgreSQL: %v", err)
		return nil, err
	}
	log.Printf("PostgreSQL connection established")

	ctx := context.Background()
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	log.Printf("Creating keys repository...")
	keysRepo := repository.NewVerifiableRepository[*Keys](store, true, true, nil)

	log.Printf("Querying existing keys from database...")
	records := []*Keys{}
	if err := keysRepo.Select(ctx, &records, expressions.Equal("purpose", PURPOSE), orderings.Descending("sequence_number"), nil); err != nil {
		log.Printf("Failed to query keys: %v", err)
		return nil, err
	}
	log.Printf("Found %d existing key records", len(records))

	log.Printf("Initializing PKCS#11 signing key...")
	key, err := NewSigningKey()
	if err != nil {
		log.Printf("Failed to initialize signing key: %v", err)
		return nil, err
	}
	log.Printf("PKCS#11 signing key initialized")

	var record *Keys
	if len(records) > 0 {
		log.Printf("Loading existing key (sequence %d)...", records[0].SequenceNumber)
		record = records[0]
		key.loadKey(LABEL, record.SequenceNumber)
		log.Printf("Existing key loaded successfully")
	} else {
		log.Printf("No existing keys found, generating new key pair...")
		ctx := context.Background()
		ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()

		log.Printf("Generating key 0...")
		if err := key.generateKey(LABEL, 0); err != nil {
			return nil, err
		}
		log.Printf("Key 0 generated successfully")

		log.Printf("Generating key 1...")
		if err := key.generateKey(LABEL, 1); err != nil {
			return nil, err
		}
		log.Printf("Key 1 generated successfully")

		log.Printf("Exporting public key from key 1...")
		nextPublicKey, err := key.publicKey(LABEL, 1)
		if err != nil {
			log.Printf("Failed to export public key: %v", err)
			return nil, err
		}
		log.Printf("Public key exported successfully")

		log.Printf("Loading key 0...")
		if err := key.loadKey(LABEL, 0); err != nil {
			return nil, err
		}
		log.Printf("Key 0 loaded successfully")

		log.Printf("Computing rotation hash...")
		rotationHash := CESRBlake3Sum(nextPublicKey)
		record = &Keys{
			Purpose:      PURPOSE,
			PublicKey:    key.cesrPublicKey,
			RotationHash: rotationHash,
		}

		log.Printf("Saving key record to database...")
		if err := keysRepo.CreateVersion(ctx, record); err != nil {
			log.Printf("Failed to save key record: %v", err)
			return nil, err
		}
		log.Printf("Key record saved successfully")

		recordJson, err := json.Marshal(record)
		if err != nil {
			return nil, err
		}

		signature, err := key.Sign([]byte(recordJson))
		if err != nil {
			return nil, err
		}

		redisMessage := struct {
			Payload   *Keys  `json:"payload"`
			Signature string `json:"signature"`
		}{
			Payload:   record,
			Signature: signature,
		}

		redisJson, err := json.Marshal(redisMessage)
		if err != nil {
			return nil, err
		}

		redisHost := os.Getenv("REDIS_HOST")
		if redisHost == "" {
			redisHost = "redis:6379"
		}

		redisDbHsmKeysString := os.Getenv("REDIS_DB_HSM_KEYS")
		redisDbHsmKeys, err := strconv.Atoi(redisDbHsmKeysString)
		if err != nil {
			return nil, err
		}

		hsmKeysClient := redis.NewClient(&redis.Options{
			Addr: redisHost,
			DB:   redisDbHsmKeys,
		})

		// Retry Redis Set operation to handle connection drops gracefully
		_, err = retryRedisOperation(ctx, func() (struct{}, error) {
			return struct{}{}, hsmKeysClient.Set(ctx, record.Id, redisJson, 0).Err()
		})
		if err != nil {
			return nil, err
		}

		_ = hsmKeysClient.Close()
	}

	key.identity = record.Prefix
	key.generationId = record.Id

	log.Printf("HSM initialized successfully")

	return &HSMServer{
		key:      key,
		keysRepo: keysRepo,
	}, nil
}

func (s *HSMServer) rotateSigningKey() error {
	ctx := context.Background()
	ctx, cancel1 := context.WithTimeout(ctx, 5*time.Second)
	defer cancel1()

	records := []*Keys{}

	if err := s.keysRepo.Select(ctx, &records, expressions.Equal("purpose", PURPOSE), orderings.Descending("sequence_number"), nil); err != nil {
		return err
	}

	if len(records) == 0 {
		return fmt.Errorf("no record found")
	}

	record := records[0]

	if err := s.key.generateKey(LABEL, record.SequenceNumber+2); err != nil {
		return err
	}
	nextPublicKey, err := s.key.publicKey(LABEL, record.SequenceNumber+2)
	if err != nil {
		return err
	}

	rotationHash := CESRBlake3Sum(nextPublicKey)

	if err := s.key.loadKey(LABEL, record.SequenceNumber+1); err != nil {
		return err
	}

	record.PublicKey = s.key.cesrPublicKey
	record.RotationHash = rotationHash

	ctx = context.Background()
	ctx, cancel2 := context.WithTimeout(ctx, 5*time.Second)
	defer cancel2()

	if err := s.keysRepo.CreateVersion(ctx, record); err != nil {
		return err
	}

	s.key.generationId = record.Id

	recordJson, err := json.Marshal(record)
	if err != nil {
		return err
	}

	signature, err := s.key.Sign([]byte(recordJson))
	if err != nil {
		return err
	}

	redisMessage := struct {
		Payload   *Keys  `json:"payload"`
		Signature string `json:"signature"`
	}{
		Payload:   record,
		Signature: signature,
	}

	redisJson, err := json.Marshal(redisMessage)
	if err != nil {
		return err
	}

	redisHost := os.Getenv("REDIS_HOST")
	if redisHost == "" {
		redisHost = "redis:6379"
	}

	redisDbHsmKeysString := os.Getenv("REDIS_DB_HSM_KEYS")
	redisDbHsmKeys, err := strconv.Atoi(redisDbHsmKeysString)
	if err != nil {
		return err
	}

	hsmKeysClient := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   redisDbHsmKeys,
	})

	// Retry Redis Set operation to handle connection drops gracefully
	_, err = retryRedisOperation(ctx, func() (struct{}, error) {
		return struct{}{}, hsmKeysClient.Set(ctx, record.Id, redisJson, 0).Err()
	})
	if err != nil {
		return err
	}

	_ = hsmKeysClient.Close()

	return nil
}

func (s *HSMServer) handleSign(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "invalid request"})
		return
	}

	// Validate that payload is valid JSON
	if !json.Valid(req.Payload) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "invalid JSON payload"})
		return
	}

	// Construct the body (payload + hsmIdentity)
	body := SignResponseBody{
		Payload: req.Payload,
		Hsm: SignHsm{
			Identity:     s.key.identity,
			GenerationId: s.key.generationId,
		},
	}

	// Serialize the body to JSON for signing
	bodyJSON, err := json.Marshal(body)
	if err != nil {
		log.Printf("Failed to marshal body: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "failed to marshal body"})
		return
	}

	// Sign the body JSON
	signature, err := s.key.Sign(bodyJSON)
	if err != nil {
		log.Printf("Sign error: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "signing failed"})
		return
	}

	// Return body and CESR signature
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(SignResponse{
		Body:      body,
		Signature: signature,
	})
}

func (s *HSMServer) handleRotate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	if err := s.rotateSigningKey(); err != nil {
		fmt.Fprintf(w, `{"error":"internal error"}`)
		return
	}

	fmt.Fprintf(w, `{"newPublicKey":"%s"}`, s.key.cesrPublicKey)
}

func (s *HSMServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"status":"healthy"}`)
}

func main() {
	server, err := NewHSMServer()
	if err != nil {
		log.Fatalf("Failed to initialize HSM server: %v", err)
	}
	defer server.key.Close()

	// Log public key at startup
	http.HandleFunc("/sign", server.handleSign)
	http.HandleFunc("/rotate", server.handleRotate)
	http.HandleFunc("/health", server.handleHealth)

	port := os.Getenv("PORT")
	if port == "" {
		port = "11111"
	}

	log.Printf("HSM server listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
