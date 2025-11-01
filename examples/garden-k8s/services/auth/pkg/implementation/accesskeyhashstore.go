package implementation

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"
)

type AccessKeyHashStore struct {
	lifetime time.Duration
	client   *redis.Client
}

func NewAccessKeyHashStore(lifetime time.Duration) (*AccessKeyHashStore, error) {
	redisHost := os.Getenv("REDIS_HOST")
	if redisHost == "" {
		redisHost = "redis:6379"
	}

	redisDbAccessKeyHashString := os.Getenv("REDIS_DB_ACCESS_KEYHASH")

	redisDbAccessKeyHash, err := strconv.Atoi(redisDbAccessKeyHashString)
	if err != nil {
		return nil, err
	}

	client := redis.NewClient(&redis.Options{
		Addr: redisHost,
		DB:   redisDbAccessKeyHash,
	})

	return &AccessKeyHashStore{
		lifetime: lifetime,
		client:   client,
	}, nil
}

func (s AccessKeyHashStore) Lifetime() time.Duration {
	return s.lifetime
}

func (s AccessKeyHashStore) Reserve(ctx context.Context, keyHash string) error {
	// Retry Redis Exists operation to handle connection drops gracefully
	exists, err := retryRedisOperation(ctx, func() (int64, error) {
		return s.client.Exists(ctx, keyHash).Result()
	})
	if err != nil {
		return err
	}

	if exists > 0 {
		return fmt.Errorf("already exists")
	}

	// Retry Redis Set operation to handle connection drops gracefully
	_, err = retryRedisOperation(ctx, func() (struct{}, error) {
		return struct{}{}, s.client.Set(ctx, keyHash, true, s.lifetime).Err()
	})
	if err != nil {
		return err
	}

	return nil
}
