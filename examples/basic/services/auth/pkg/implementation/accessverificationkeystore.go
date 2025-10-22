package implementation

import (
	"context"
	"os"
	"strconv"

	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/redis/go-redis/v9"
)

type AccessVerificationKeyStore struct {
	client *redis.Client
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

	return &AccessVerificationKeyStore{
		client: accessClient,
	}, nil
}

func (s AccessVerificationKeyStore) Get(ctx context.Context, identity string) (cryptointerfaces.VerificationKey, error) {
	verificationKeyString, err := s.client.Get(ctx, identity).Result()
	if err != nil {
		return nil, err
	}

	verificationKey := NewVerificationKey(verificationKeyString)

	return verificationKey, nil
}

func (s AccessVerificationKeyStore) CloseClient() error {
	return s.client.Close()
}
