package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/jasoncolburne/better-auth-go/api"
	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/examples/encoding"
	"github.com/jasoncolburne/better-auth-go/examples/storage"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/redis/go-redis/v9"
)

type TokenAttributes struct {
	PermissionsByRole map[string][]string `json:"permissionsByRole"`
}

type Server struct {
	ba                *api.BetterAuthServer[TokenAttributes]
	av                *api.AccessVerifier[TokenAttributes]
	serverAccessKey   cryptointerfaces.SigningKey
	serverResponseKey cryptointerfaces.SigningKey
}

func NewServer() (*Server, error) {
	accessLifetime := 15 * time.Minute
	accessWindow := 30 * time.Second
	refreshLifetime := 12 * time.Hour
	authenticationChallengeLifetime := 1 * time.Minute

	hasher := crypto.NewBlake3()
	verifier := crypto.NewSecp256r1Verifier()
	noncer := crypto.NewNoncer()

	accessKeyHashStore := storage.NewInMemoryTimeLockStore(refreshLifetime)
	accessNonceStore := storage.NewInMemoryTimeLockStore(accessWindow)
	authenticationKeyStore := storage.NewInMemoryAuthenticationKeyStore(hasher)
	authenticationNonceStore := storage.NewInMemoryAuthenticationNonceStore(authenticationChallengeLifetime)
	recoveryHashStore := storage.NewInMemoryRecoveryHashStore()

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
				KeyHash: accessKeyHashStore,
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

	accessKeyStore := storage.NewVerificationKeyStore()
	serverAccessIdentity, err := serverAccessKey.Identity()
	if err != nil {
		return nil, err
	}
	accessKeyStore.Add(serverAccessIdentity, serverAccessKey)

	av := api.NewAccessVerifier[TokenAttributes](
		&api.VerifierCryptoContainer{
			Verifier: verifier,
		},
		&api.VerifierEncodingContainer{
			TokenEncoder: tokenEncoder,
			Timestamper:  timestamper,
		},
		&api.VerifierStoreContainer{
			AccessNonce: accessNonceStore,
			AccessKey:   accessKeyStore,
		},
	)

	return &Server{
		ba:                ba,
		av:                av,
		serverAccessKey:   serverAccessKey,
		serverResponseKey: serverResponseKey,
	}, nil
}

func wrapResponse(w http.ResponseWriter, r *http.Request, logic func(message string) (string, error)) {
	var reply string

	message, err := io.ReadAll(r.Body)

	if err == nil {
		reply, err = logic(string(message))
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
	wrapResponse(w, r, func(message string) (string, error) {
		return s.ba.CreateSession(message, TokenAttributes{
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

	// Handle OPTIONS for CORS
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == "OPTIONS" {
			corsHandler(w, r)
			return
		}
		http.NotFound(w, r)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Auth server starting on port %s", port)
	return http.ListenAndServe(":"+port, nil)
}

// registerKeysInRedis writes the server's access and response public keys to Redis
func registerKeysInRedis(accessKey, responseKey cryptointerfaces.SigningKey) error {
	redisHost := os.Getenv("REDIS_HOST")
	if redisHost == "" {
		redisHost = "redis:6379"
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

	// Connect to Redis DB 0 (Access Keys)
	accessClient := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   0,
	})
	defer accessClient.Close()

	// Write access key with 24 hour TTL: SET <public_key> <public_key> EX 86400
	if err := accessClient.Set(ctx, accessPublicKey, accessPublicKey, 24*time.Hour).Err(); err != nil {
		return fmt.Errorf("failed to write access key to Redis: %w", err)
	}
	log.Printf("Registered access key in Redis DB 0 (TTL: 24 hours)")

	// Connect to Redis DB 1 (Response Keys)
	responseClient := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   1,
	})
	defer responseClient.Close()

	// Write response key with 12 hour 1 minute TTL: SET <public_key> <public_key> EX 43260
	if err := responseClient.Set(ctx, responsePublicKey, responsePublicKey, 12*time.Hour+time.Minute).Err(); err != nil {
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

	// Register keys in Redis
	if err := registerKeysInRedis(server.serverAccessKey, server.serverResponseKey); err != nil {
		log.Fatalf("Failed to register keys in Redis: %v", err)
	}

	// Schedule server shutdown after 12 hours for key rotation
	time.AfterFunc(12*time.Hour, func() {
		log.Printf("Server lifetime expired (12 hours), shutting down for key rotation")
		os.Exit(0)
	})
	log.Printf("Server will shutdown in 12 hours for automatic key rotation")

	if err := server.StartServer(); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
