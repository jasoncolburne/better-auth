package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jasoncolburne/better-auth-go/api"
	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/examples/encoding"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/jasoncolburne/better-auth/examples/garden-k8s/auth/pkg/db"
	"github.com/jasoncolburne/better-auth/examples/garden-k8s/auth/pkg/implementation"
	"github.com/jasoncolburne/better-auth/examples/garden-k8s/auth/pkg/models"
	"github.com/redis/go-redis/v9"
)

type TokenAttributes struct {
	PermissionsByRole map[string][]string `json:"permissionsByRole"`
}

type Server struct {
	ba                         *api.BetterAuthServer[TokenAttributes]
	serverAccessKey            cryptointerfaces.SigningKey
	serverResponseKey          cryptointerfaces.SigningKey
	accessVerificationKeyStore *implementation.AccessVerificationKeyStore
	authenticationKeyStore     *implementation.AuthenticationKeyStore
	server                     http.Server
}

func (s *Server) CloseClients() {
	if s.accessVerificationKeyStore != nil {
		_ = s.accessVerificationKeyStore.CloseClients()
	}

	if s.authenticationKeyStore != nil {
		_ = s.authenticationKeyStore.CloseRevokedDevicesClient()
	}
}

func NewServer() (*Server, error) {
	serverLifetime := 12 * time.Hour
	accessLifetime := 15 * time.Minute
	refreshLifetime := 12 * time.Hour
	authenticationChallengeLifetime := 1 * time.Minute

	hasher := crypto.NewBlake3()
	verifier := crypto.NewSecp256r1Verifier()
	noncer := crypto.NewNoncer()

	accessKeyHashStore, err := implementation.NewAccessKeyHashStore(refreshLifetime)
	if err != nil {
		return nil, err
	}

	accessVerificationKeyStore, err := implementation.NewAccessVerificationKeyStore(serverLifetime, refreshLifetime)
	if err != nil {
		return nil, err
	}

	migrations := []string{
		models.AUTHENTICATION_KEYS_TABLE_SQL,
		models.IDENTITY_TABLE_SQL,
		models.AUTHENTICATION_NONCE_TABLE_SQL,
		models.RECOVERY_HASH_TABLE_SQL,
	}

	user := os.Getenv("POSTGRES_USER")
	password := os.Getenv("POSTGRES_PASSWORD")
	database := os.Getenv("POSTGRES_DATABASE")
	host := os.Getenv("POSTGRES_HOST")
	port := os.Getenv("POSTGRES_PORT")

	dsn := fmt.Sprintf(
		"user=%s password=%s dbname=%s host=%s port=%s sslmode=disable",
		user,
		password,
		database,
		host,
		port,
	)

	store, err := db.NewPostgreSQLStore(context.Background(), dsn, migrations)
	if err != nil {
		return nil, err
	}

	authenticationKeyStore, err := implementation.NewAuthenticationKeyStore(store, accessLifetime)
	if err != nil {
		return nil, err
	}

	// TODO: implement these two in postgres
	authenticationNonceStore := implementation.NewAuthenticationNonceStore(store, authenticationChallengeLifetime)
	recoveryHashStore := implementation.NewRecoveryHashStore(store)

	identityVerifier := encoding.NewMockIdentityVerifier(hasher)
	timestamper := encoding.NewRfc3339Nano()
	tokenEncoder := encoding.NewTokenEncoder[TokenAttributes]()

	serverResponseKey, err := crypto.NewSecp256r1()
	if err != nil {
		return nil, err
	}

	serverAccessKey, err := crypto.NewSecp256r1()
	if err != nil {
		return nil, err
	}

	ba := api.NewBetterAuthServer[TokenAttributes](
		&api.CryptoContainer{
			Hasher: hasher,
			KeyPair: &api.KeyPairContainer{
				Access:   serverAccessKey,
				Response: serverResponseKey,
			},
			Noncer:   noncer,
			Verifier: verifier,
		},
		&api.EncodingContainer{
			IdentityVerifier: identityVerifier,
			Timestamper:      timestamper,
			TokenEncoder:     tokenEncoder,
		},
		&api.ExpiryContainer{
			Access:  accessLifetime,
			Refresh: refreshLifetime,
		},
		&api.StoresContainer{
			Access: &api.AccessStoreContainer{
				KeyHash:         accessKeyHashStore,
				VerificationKey: accessVerificationKeyStore,
			},
			Authentication: &api.AuthenticationStoreContainer{
				Key:   authenticationKeyStore,
				Nonce: authenticationNonceStore,
			},
			Recovery: &api.RecoveryStoreContainer{
				Hash: recoveryHashStore,
			},
		},
	)

	return &Server{
		ba:                         ba,
		serverAccessKey:            serverAccessKey,
		serverResponseKey:          serverResponseKey,
		accessVerificationKeyStore: accessVerificationKeyStore,
		authenticationKeyStore:     authenticationKeyStore,
	}, nil
}

func wrapResponse(w http.ResponseWriter, r *http.Request, logic func(ctx context.Context, message string) (string, error)) {
	var reply string

	message, err := io.ReadAll(r.Body)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err == nil {
		reply, err = logic(ctx, string(message))
	}

	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		reply = "{\"error\":\"an error occurred\"}"
		w.WriteHeader(http.StatusInternalServerError)
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	fmt.Fprintf(w, "%s", reply)
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.CreateAccount)
}

func (s *Server) recover(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.RecoverAccount)
}

func (s *Server) delete(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.DeleteAccount)
}

func (s *Server) link(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.LinkDevice)
}

func (s *Server) unlink(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.UnlinkDevice)
}

func (s *Server) startAuthentication(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.RequestSession)
}

func (s *Server) finishAuthentication(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, func(ctx context.Context, message string) (string, error) {
		return s.ba.CreateSession(ctx, message, TokenAttributes{
			PermissionsByRole: map[string][]string{
				"user": {
					"read",
					"write",
				},
			},
		})
	})
}

func (s *Server) rotateAuthentication(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.RotateDevice)
}

func (s *Server) rotateAccess(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.RefreshSession)
}

func (s *Server) changeRecoveryKey(w http.ResponseWriter, r *http.Request) {
	wrapResponse(w, r, s.ba.ChangeRecoveryKey)
}

func (s *Server) healthCheck(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, "{\"status\":\"healthy\"}")
}

// CORS preflight handler
func corsHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
	w.WriteHeader(http.StatusOK)
}

func (s *Server) StartServer() error {
	http.HandleFunc("/health", s.healthCheck)

	http.HandleFunc("/account/create", s.create)
	http.HandleFunc("/account/recover", s.recover)
	http.HandleFunc("/account/delete", s.delete)

	http.HandleFunc("/session/request", s.startAuthentication)
	http.HandleFunc("/session/create", s.finishAuthentication)
	http.HandleFunc("/session/refresh", s.rotateAccess)

	http.HandleFunc("/device/rotate", s.rotateAuthentication)
	http.HandleFunc("/device/link", s.link)
	http.HandleFunc("/device/unlink", s.unlink)

	http.HandleFunc("/recovery/change", s.changeRecoveryKey)

	// Handle OPTIONS for CORS
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "OPTIONS" {
			corsHandler(w, r)
			return
		}
		http.NotFound(w, r)
	})

	log.Printf("Auth server starting on port 80")

	s.server = http.Server{Addr: ":80"}
	return s.server.ListenAndServe()
}

func (s *Server) StopServer() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return s.server.Shutdown(ctx)
}

// signWithHSM signs a payload using the HSM service
func signWithHSM(hsmURL string, payload implementation.KeySigningPayload) (string, error) {
	// Create request
	reqBody := struct {
		Payload implementation.KeySigningPayload `json:"payload"`
	}{
		Payload: payload,
	}
	reqJSON, err := json.Marshal(reqBody)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	// POST to HSM
	resp, err := http.Post(hsmURL+"/sign", "application/json", bytes.NewBuffer(reqJSON))
	if err != nil {
		return "", fmt.Errorf("failed to POST to HSM: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HSM returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response")
	}

	// Parse response
	var signResp struct {
		Body      implementation.KeySigningBody `json:"body"`
		Signature string                        `json:"signature"`
	}
	if err := json.Unmarshal(body, &signResp); err != nil {
		return "", fmt.Errorf("failed to decode HSM response: %w", err)
	}

	return strings.TrimSpace(string(body)), nil
}

// registerKeysInRedis writes the server's access and response public keys to Redis
func registerKeysInRedis(accessKey, responseKey cryptointerfaces.SigningKey) error {
	redisHost := os.Getenv("REDIS_HOST")
	if redisHost == "" {
		redisHost = "redis:6379"
	}

	redisDbAccessKeysString := os.Getenv("REDIS_DB_ACCESS_KEYS")
	redisDbResponseKeysString := os.Getenv("REDIS_DB_RESPONSE_KEYS")

	redisDbAccessKeys, err := strconv.Atoi(redisDbAccessKeysString)
	if err != nil {
		return err
	}

	redisDbResponseKeys, err := strconv.Atoi(redisDbResponseKeysString)
	if err != nil {
		return err
	}

	ctx := context.Background()

	// Get public keys
	accessPublicKey, err := accessKey.Public()
	if err != nil {
		return fmt.Errorf("failed to get access public key: %w", err)
	}

	responsePublicKey, err := responseKey.Public()
	if err != nil {
		return fmt.Errorf("failed to get response public key: %w", err)
	}

	// TTL constants
	accessTTL := 24 * time.Hour
	responseTTL := 12*time.Hour + time.Minute

	// Sign keys with HSM
	hsmHost := os.Getenv("HSM_HOST")
	if hsmHost == "" {
		hsmHost = "hsm"
	}
	hsmPort := os.Getenv("HSM_PORT")
	if hsmPort == "" {
		hsmPort = "11111"
	}
	hsmURL := fmt.Sprintf("http://%s:%s", hsmHost, hsmPort)

	// Sign access key (expires in 24 hours to match Redis TTL)
	accessExpiration := time.Now().Add(accessTTL).Format(time.RFC3339Nano)
	accessPayload := implementation.KeySigningPayload{
		Purpose:    "access",
		PublicKey:  accessPublicKey,
		Expiration: accessExpiration,
	}
	accessAuthorization, err := signWithHSM(hsmURL, accessPayload)
	if err != nil {
		log.Printf("Warning: Failed to sign access key with HSM: %v", err)
	} else {
		log.Printf("Access key HSM authorization (CESR): %s", accessAuthorization)
	}

	// Sign response key (expires in 12 hours + 1 minute to match Redis TTL)
	responseExpiration := time.Now().Add(responseTTL).Format(time.RFC3339Nano)
	responsePayload := implementation.KeySigningPayload{
		Purpose:    "response",
		PublicKey:  responsePublicKey,
		Expiration: responseExpiration,
	}
	responseAuthorization, err := signWithHSM(hsmURL, responsePayload)
	if err != nil {
		log.Printf("Warning: Failed to sign response key with HSM: %v", err)
	} else {
		log.Printf("Response key HSM authorization (CESR): %s", responseAuthorization)
	}

	accessClient := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   redisDbAccessKeys,
	})
	defer accessClient.Close()

	// Write access key with 24 hour TTL: SET <public_key> <public_key> EX 86400
	if err := accessClient.Set(ctx, accessPublicKey, accessAuthorization, accessTTL).Err(); err != nil {
		return fmt.Errorf("failed to write access key to Redis: %w", err)
	}
	log.Printf("Registered access key in Redis DB 0 (TTL: 24 hours)")

	responseClient := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   redisDbResponseKeys,
	})
	defer responseClient.Close()

	// Write response key with 12 hour 1 minute TTL: SET <public_key> <public_key> EX 43260
	if err := responseClient.Set(ctx, responsePublicKey, responseAuthorization, responseTTL).Err(); err != nil {
		return fmt.Errorf("failed to write response key to Redis: %w", err)
	}
	log.Printf("Registered response key in Redis DB 1 (TTL: 12 hours)")

	return nil
}

func main() {
	server, err := NewServer()
	if err != nil {
		log.Fatalf("Failed to create server: %v", err)
	}
	defer server.CloseClients()

	// Register keys in Redis
	if err := registerKeysInRedis(server.serverAccessKey, server.serverResponseKey); err != nil {
		log.Fatalf("Failed to register keys in Redis: %v", err)
	}

	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-c
		log.Println("SIGTERM received, shutting down gracefully...")
		if err := server.StopServer(); err != nil {
			log.Printf("Failed to stop server: %v", err)
		}
		os.Exit(0)
	}()

	if err := server.StartServer(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
