package implementation

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/examples/encoding"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/jasoncolburne/better-auth-go/pkg/encodinginterfaces"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/algorithms"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"
	"github.com/redis/go-redis/v9"
)

const HSM_IDENTITY = "BETTER_AUTH_HSM_IDENTITY_PLACEHOLDER"

type LogEntry struct {
	primitives.VerifiableRecorder
	Purpose      string `json:"purpose"`
	PublicKey    string `json:"publicKey"`
	RotationHash string `json:"rotationHash"`
}

type SignedLogEntry struct {
	Payload   LogEntry `json:"payload"`
	Signature string   `json:"signature"`
}

type KeyVerifier struct {
	client         *redis.Client
	verifier       cryptointerfaces.Verifier
	hasher         cryptointerfaces.Hasher
	cache          map[string]*LogEntry
	accessLifetime time.Duration
}

func NewKeyVerifier(accessLifetime time.Duration) (*KeyVerifier, error) {
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

	verifier := crypto.NewSecp256r1Verifier()
	hasher := crypto.NewBlake3()

	return &KeyVerifier{
		client:         hsmKeysClient,
		verifier:       verifier,
		hasher:         hasher,
		cache:          map[string]*LogEntry{},
		accessLifetime: accessLifetime,
	}, nil
}

func (v *KeyVerifier) Verify(
	ctx context.Context,
	signature,
	hsmIdentity,
	hsmGenerationId string,
	message []byte,
) error {
	cachedEntry, ok := v.cache[hsmGenerationId]
	if !ok {
		recordStrings, err := retryRedisOperation(ctx, func() ([]any, error) {
			keys, err := v.client.Keys(ctx, "*").Result()
			if err != nil {
				return nil, err
			}

			return v.client.MGet(ctx, keys...).Result()
		})
		if err != nil {
			return err
		}

		byPrefix := map[string][]*SignedLogEntry{}
		for _, recordString := range recordStrings {
			bytes, ok := recordString.(string)
			if !ok {
				return fmt.Errorf("unexpected type for record")
			}

			record := &SignedLogEntry{}
			if err := json.Unmarshal([]byte(bytes), record); err != nil {
				return err
			}

			prefix := record.Payload.Prefix
			list, ok := byPrefix[prefix]
			if ok {
				list = append(list, record)
				byPrefix[prefix] = list
			} else {
				byPrefix[prefix] = []*SignedLogEntry{record}
			}
		}

		for prefix, records := range byPrefix {
			slices.SortFunc(records, func(a *SignedLogEntry, b *SignedLogEntry) int {
				if a.Payload.SequenceNumber < b.Payload.SequenceNumber {
					return -1
				}

				if a.Payload.SequenceNumber > b.Payload.SequenceNumber {
					return 1
				}

				return 0
			})

			byPrefix[prefix] = records
		}

		// verify data & signatures
		for _, records := range byPrefix {
			for _, record := range records {
				payload := record.Payload

				if payload.SequenceNumber == 0 {
					if err := algorithms.VerifyPrefixAndData(&payload); err != nil {
						return err
					}
				} else {
					if err := algorithms.VerifyAddressAndData(&payload); err != nil {
						return err
					}
				}

				message, err := json.Marshal(payload)
				if err != nil {
					return err
				}

				if err := v.verifier.Verify(record.Signature, payload.PublicKey, message); err != nil {
					return err
				}
			}
		}

		// verify chains
		for _, records := range byPrefix {
			lastId := ""
			lastRotationHash := ""
			for i, record := range records {
				payload := record.Payload

				if int(payload.SequenceNumber) != i {
					return fmt.Errorf("bad sequence number")
				}

				if payload.SequenceNumber != 0 {
					if lastId != *payload.Previous {
						return fmt.Errorf("broken chain")
					}

					hash := v.hasher.Sum([]byte(payload.PublicKey))

					if !strings.EqualFold(hash, lastRotationHash) {
						return fmt.Errorf("bad commitment")
					}
				}

				lastId = payload.Id
				lastRotationHash = payload.RotationHash
			}
		}

		// verify prefix
		records, ok := byPrefix[HSM_IDENTITY]
		if !ok {
			return fmt.Errorf("hsm identity not found")
		}

		for i := len(records) - 1; i >= 0; i-- {
			payload := records[i].Payload

			v.cache[payload.Id] = &payload

			when := (time.Time)(*payload.CreatedAt)
			// server restart threshold + token lifetime
			if when.Add(v.accessLifetime + 12*time.Hour).Before(time.Now()) {
				break
			}
		}

		cachedEntry, ok = v.cache[hsmGenerationId]
		if !ok {
			return fmt.Errorf("can't find valid public key")
		}
	}

	if cachedEntry.Prefix != hsmIdentity {
		return fmt.Errorf("incorrect identity (expected hsm.identity == prefix)")
	}

	if cachedEntry.Purpose != "key-authorization" {
		return fmt.Errorf("incorrect purpose (expected key-authorization)")
	}

	publicKey := cachedEntry.PublicKey

	// verify message signature
	if err := v.verifier.Verify(signature, publicKey, message); err != nil {
		return err
	}

	return nil
}

type KeySigningBody struct {
	Payload KeySigningPayload `json:"payload"`
	Hsm     KeySigningHsm     `json:"hsm"`
}

type KeySigningHsm struct {
	Identity     string `json:"identity"`
	GenerationId string `json:"generationId"`
}

type KeySigningPayload struct {
	Purpose    string `json:"purpose"`
	PublicKey  string `json:"publicKey"`
	Expiration string `json:"expiration"`
}

type AccessVerificationKeyStore struct {
	client      *redis.Client
	verifier    *KeyVerifier
	timestamper encodinginterfaces.Timestamper
}

func NewAccessVerificationKeyStore(accessLifetime time.Duration) (*AccessVerificationKeyStore, error) {
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

	verifier, err := NewKeyVerifier(accessLifetime)
	if err != nil {
		return nil, err
	}

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

	if err := s.verifier.Verify(
		ctx,
		verificationStruct.Signature,
		responseStruct.Body.Hsm.Identity,
		responseStruct.Body.Hsm.GenerationId,
		verificationStruct.Body,
	); err != nil {
		return nil, err
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

func (s AccessVerificationKeyStore) CloseClients() error {
	_ = s.verifier.client.Close()
	return s.client.Close()
}
