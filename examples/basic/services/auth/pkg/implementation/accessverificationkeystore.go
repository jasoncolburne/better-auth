package implementation

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/examples/encoding"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/jasoncolburne/better-auth-go/pkg/encodinginterfaces"
	"github.com/redis/go-redis/v9"
)

const HSM_PUBLIC_KEY = "1AAIAjIhd42fcH957TzvXeMbgX4AftiTT7lKmkJ7yHy3dph9"

type KeySigningBody struct {
	Payload     KeySigningPayload `json:"payload"`
	HsmIdentity string            `json:"hsmIdentity"`
}

type KeySigningPayload struct {
	Purpose    string `json:"purpose"`
	PublicKey  string `json:"publicKey"`
	Expiration string `json:"expiration"`
}

type AccessVerificationKeyStore struct {
	client      *redis.Client
	verifier    cryptointerfaces.Verifier
	timestamper encodinginterfaces.Timestamper
}

func NewAccessVerificationKeyStore() (*AccessVerificationKeyStore, error) {
	redisHost := os.Getenv("REDIS_HOST")
	if redisHost == "" {
		redisHost = "redis:6379"
	}

	redisDbAccessKeysString := os.Getenv("REDIS_DB_ACCESS_KEYS")

	redisDbAccessKeys, err := strconv.Atoi(redisDbAccessKeysString)
	if err != nil {
		return nil, err
	}

	accessClient := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   redisDbAccessKeys,
	})

	verifier := crypto.NewSecp256r1Verifier()
	timestamper := encoding.NewRfc3339Nano()

	return &AccessVerificationKeyStore{
		client:      accessClient,
		verifier:    verifier,
		timestamper: timestamper,
	}, nil
}

func (s AccessVerificationKeyStore) Get(ctx context.Context, identity string) (cryptointerfaces.VerificationKey, error) {
	// Retry Redis Get operation to handle connection drops gracefully
	verificationAuthorization, err := retryRedisOperation(ctx, func() (string, error) {
		return s.client.Get(ctx, identity).Result()
	})
	if err != nil {
		return nil, err
	}

	responseStruct := struct {
		Body      KeySigningBody `json:"body"`
		Signature string         `json:"signature"`
	}{}

	if err := json.Unmarshal([]byte(verificationAuthorization), &responseStruct); err != nil {
		return nil, err
	}

	verificationStruct := struct {
		Body      json.RawMessage `json:"body"`
		Signature string          `json:"signature"`
	}{}

	if err := json.Unmarshal([]byte(verificationAuthorization), &verificationStruct); err != nil {
		return nil, err
	}

	if err := s.verifier.Verify(verificationStruct.Signature, HSM_PUBLIC_KEY, verificationStruct.Body); err != nil {
		return nil, err
	}

	if !strings.EqualFold(responseStruct.Body.HsmIdentity, HSM_PUBLIC_KEY) {
		return nil, fmt.Errorf("unknown hsm key")
	}

	if !strings.EqualFold(responseStruct.Body.Payload.Purpose, "access") {
		return nil, fmt.Errorf("incorrect purpose")
	}

	expiration, err := s.timestamper.Parse(responseStruct.Body.Payload.Expiration)
	if err != nil {
		return nil, fmt.Errorf("invalid timestamp")
	}

	if time.Now().After(expiration) {
		return nil, fmt.Errorf("expired key")
	}

	verificationKey := NewVerificationKey(responseStruct.Body.Payload.PublicKey)

	return verificationKey, nil
}

func (s AccessVerificationKeyStore) CloseClient() error {
	return s.client.Close()
}
