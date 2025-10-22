package main

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/jasoncolburne/verifiable-storage-go/pkg/data"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/clauses"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/expressions"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/orderings"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/repository"

	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/redis/go-redis/v9"
)

type VerificationKey struct {
	verifier  cryptointerfaces.Verifier
	publicKey string
}

func NewVerificationKey(publicKey string) *VerificationKey {
	verifier := crypto.NewSecp256r1Verifier()

	return &VerificationKey{
		verifier:  verifier,
		publicKey: publicKey,
	}
}

func (v VerificationKey) Verifier() cryptointerfaces.Verifier {
	return v.verifier
}

func (v VerificationKey) Public() (string, error) {
	return v.publicKey, nil
}

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
	exists, err := s.client.Exists(ctx, keyHash).Result()
	if err != nil {
		return err
	}

	if exists > 0 {
		return fmt.Errorf("already exists")
	}

	if err := s.client.Set(ctx, keyHash, true, s.lifetime).Err(); err != nil {
		return err
	}

	return nil
}

// this table omits a nonce for more determinism
const AUTHENTICATION_KEYS_TABLE_SQL = `
	CREATE TABLE IF NOT EXISTS authenticationkeys (
		-- Standard fields
		id              	TEXT PRIMARY KEY,
		prefix				TEXT NOT NULL,
		previous        	TEXT,
		sequence_number 	BIGINT NOT NULL,

		-- Optional fields
		created_at          TIMESTAMP NOT NULL,

		-- Model-specific fields
		identity 			TEXT NOT NULL,
		device              TEXT NOT NULL,
		public_key			TEXT NOT NULL,
		rotation_hash       TEXT NOT NULL,
		revoked             BOOLEAN NOT NULL,

		-- Uniqueness constraint for sequence numbers
		UNIQUE(prefix, sequence_number),

		-- Uniqueness constraint for devices
		UNIQUE(identity, device, sequence_number)
	);
`

type AuthenticationKeys struct {
	primitives.VerifiableRecorder
	Identity     string `db:"identity" json:"identity"`
	Device       string `db:"device" json:"device"`
	PublicKey    string `db:"public_key" json:"publicKey"`
	RotationHash string `db:"rotation_hash" json:"rotationHash"`
	Revoked      bool   `db:"revoked" json:"revoked"`
}

func (*AuthenticationKeys) TableName() string {
	return "authenticationkeys"
}

// this table omits a nonce for more determinism
const IDENTITY_TABLE_SQL = `
	CREATE TABLE IF NOT EXISTS identities (
		-- Standard fields
		id              	TEXT PRIMARY KEY,
		prefix				TEXT NOT NULL,
		previous        	TEXT,
		sequence_number 	BIGINT NOT NULL,

		-- Optional fields
		created_at          TIMESTAMP NOT NULL,

		-- Model-specific fields
		identity 			TEXT NOT NULL,
		deleted             BOOLEAN NOT NULL,

		-- Uniqueness constraint for sequence numbers
		UNIQUE(prefix, sequence_number),

		-- Uniqueness constraint for identity
		UNIQUE(identity, sequence_number)
	);
`

type Identity struct {
	primitives.VerifiableRecorder
	Identity string `db:"identity" json:"identity"`
	Deleted  bool   `db:"deleted" json:"deleted"`
}

func (*Identity) TableName() string {
	return "identities"
}

const AUTHENTICATION_NONCE_TABLE_SQL = `
	CREATE TABLE IF NOT EXISTS authenticationnonces (
		-- Standard fields
		id              	TEXT PRIMARY KEY,
		prefix				TEXT NOT NULL,
		previous        	TEXT,
		sequence_number 	BIGINT NOT NULL,

		-- Optional fields
		created_at          TIMESTAMP NOT NULL,

		-- Model-specific fields
		identity 			TEXT NOT NULL,
		challenge_nonce		TEXT NOT NULL,
		used                BOOLEAN NOT NULL,

		-- Uniqueness constraint for sequence numbers
		UNIQUE(prefix, sequence_number),

		-- Uniqueness for safety/replay
		UNIQUE(challenge_nonce, sequence_number)
	);
`

type AuthenticationNonce struct {
	primitives.VerifiableRecorder
	Identity       string `db:"identity" json:"identity"`
	ChallengeNonce string `db:"challenge_nonce" json:"challengeNonce"`
	Used           bool   `db:"used" json:"used"`
}

func (*AuthenticationNonce) TableName() string {
	return "authenticationnonces"
}

const RECOVERY_HASH_TABLE_SQL = `
	CREATE TABLE IF NOT EXISTS recoveryhashes (
		-- Standard fields
		id              	TEXT PRIMARY KEY,
		prefix				TEXT NOT NULL,
		previous        	TEXT,
		sequence_number 	BIGINT NOT NULL,

		-- Optional fields
		created_at          TIMESTAMP NOT NULL,

		-- Model-specific fields
		identity 			TEXT NOT NULL,
		recovery_hash 		TEXT NOT NULL,

		-- Uniqueness constraint for sequence numbers
		UNIQUE(prefix, sequence_number),

		-- Uniqueness constraint for identity
		UNIQUE(identity, sequence_number)
	);
`

type RecoveryHash struct {
	primitives.VerifiableRecorder
	Identity     string `db:"identity" json:"identity"`
	RecoveryHash string `db:"recovery_hash" json:"recovery_hash"`
}

func (*RecoveryHash) TableName() string {
	return "recoveryhashes"
}

type AuthenticationNonceStore struct {
	lifetime                      time.Duration
	noncer                        cryptointerfaces.Noncer
	identityRepository            repository.Repository[*Identity]
	authenticationNonceRepository repository.Repository[*AuthenticationNonce]
}

func NewAuthenticationNonceStore(store data.Store, lifetime time.Duration) *AuthenticationNonceStore {
	noncer := crypto.NewNoncer()

	// a better pattern would be injection of these repos
	identityRepository := repository.NewVerifiableRepository[*Identity](
		store,
		true,
		true,
		nil, // nil for determinism
	)

	authenticationNonceRepository := repository.NewVerifiableRepository[*AuthenticationNonce](
		store,
		true,
		true,
		nil,
	)

	return &AuthenticationNonceStore{
		lifetime:                      lifetime,
		noncer:                        noncer,
		identityRepository:            identityRepository,
		authenticationNonceRepository: authenticationNonceRepository,
	}
}

func (s AuthenticationNonceStore) Generate(ctx context.Context, identity string) (string, error) {
	identityRecord := &Identity{}
	if err := s.identityRepository.Get(
		ctx,
		identityRecord,
		expressions.Equal("identity", identity),
		orderings.Descending("sequence_number"),
	); err != nil {
		return "", err
	}

	if !strings.EqualFold(identityRecord.Identity, identity) {
		return "", fmt.Errorf("mismatched identity")
	}

	if identityRecord.Deleted {
		return "", fmt.Errorf("deleted identity")
	}

	nonce, err := s.noncer.Generate128()
	if err != nil {
		return "", err
	}

	record := &AuthenticationNonce{
		Identity:       identity,
		ChallengeNonce: nonce,
	}

	if err := s.authenticationNonceRepository.CreateVersion(ctx, record); err != nil {
		return "", err
	}

	return nonce, nil
}

func (s AuthenticationNonceStore) Verify(ctx context.Context, nonce string) (string, error) {
	record := &AuthenticationNonce{}
	if err := s.authenticationNonceRepository.Get(ctx, record, expressions.Equal("challenge_nonce", nonce), orderings.Descending("sequence_number")); err != nil {
		return "", err
	}

	if record.Used {
		return "", fmt.Errorf("challenge already used")
	}

	timestamp := (*time.Time)(record.CreatedAt)

	if timestamp.Add(s.lifetime).Before(time.Now()) {
		return "", fmt.Errorf("challenge expired")
	}

	record.Used = true

	if err := s.authenticationNonceRepository.CreateVersion(ctx, record); err != nil {
		return "", err
	}

	return record.Identity, nil
}

type RecoveryHashStore struct {
	recoveryHashRepository repository.Repository[*RecoveryHash]
}

func NewRecoveryHashStore(store data.Store) *RecoveryHashStore {
	recoveryHashRepository := repository.NewVerifiableRepository[*RecoveryHash](store, true, true, nil)
	return &RecoveryHashStore{
		recoveryHashRepository: recoveryHashRepository,
	}
}

func (s RecoveryHashStore) Register(ctx context.Context, identity, recoveryHash string) error {
	record := &RecoveryHash{
		Identity:     identity,
		RecoveryHash: recoveryHash,
	}

	// uniqueness constraint protects us from duplication
	if err := s.recoveryHashRepository.CreateVersion(ctx, record); err != nil {
		return err
	}

	return nil
}

func (s RecoveryHashStore) Rotate(ctx context.Context, identity, oldHash, newHash string) error {
	record := &RecoveryHash{}
	if err := s.recoveryHashRepository.Get(ctx, record, expressions.Equal("identity", identity), orderings.Descending("sequence_number")); err != nil {
		return err
	}

	if !strings.EqualFold(oldHash, record.RecoveryHash) {
		return fmt.Errorf("old hash doesn't match")
	}

	record.RecoveryHash = newHash

	if err := s.recoveryHashRepository.CreateVersion(ctx, record); err != nil {
		return err
	}

	return nil
}

func (s RecoveryHashStore) Change(ctx context.Context, identity, newHash string) error {
	record := &RecoveryHash{}
	if err := s.recoveryHashRepository.Get(ctx, record, expressions.Equal("identity", identity), orderings.Descending("sequence_number")); err != nil {
		return err
	}

	record.RecoveryHash = newHash

	if err := s.recoveryHashRepository.CreateVersion(ctx, record); err != nil {
		return err
	}

	return nil
}

type AuthenticationKeyStore struct {
	store  data.Store
	hasher cryptointerfaces.Hasher

	identityRepository           repository.Repository[*Identity]
	authenticationKeysRepository repository.Repository[*AuthenticationKeys]
}

func NewAuthenticationKeyStore(store data.Store) (*AuthenticationKeyStore, error) {
	hasher := crypto.NewBlake3()

	identityRepository := repository.NewVerifiableRepository[*Identity](
		store,
		true,
		true,
		nil, // nil for determinism
	)

	authenticationKeysRepository := repository.NewVerifiableRepository[*AuthenticationKeys](
		store,
		true,
		true,
		nil, // nil for determinism
	)

	return &AuthenticationKeyStore{
		store:                        store,
		hasher:                       hasher,
		identityRepository:           identityRepository,
		authenticationKeysRepository: authenticationKeysRepository,
	}, nil
}

func (s AuthenticationKeyStore) identityExists(ctx context.Context, identity string) (bool, error) {
	buffer := []*Identity{}

	if err := s.identityRepository.ListLatestByPrefix(
		ctx,
		&buffer,
		expressions.Equal("identity", identity),
		expressions.Equal("deleted", false),
		nil,
		nil,
	); err != nil {
		return false, err
	}

	if len(buffer) == 0 {
		return false, nil
	}

	if buffer[0].Deleted {
		return false, fmt.Errorf("account deleted")
	}

	return true, nil
}

func (s AuthenticationKeyStore) Register(ctx context.Context, identity, device, publicKey, rotationHash string, existingIdentity bool) error {
	actuallyExists, err := s.identityExists(ctx, identity)
	if err != nil {
		return err
	}

	if err := s.store.BeginTransaction(ctx, nil); err != nil {
		return err
	}

	committed := false
	defer func() {
		if !committed {
			s.store.RollbackTransaction()
		}
	}()

	if existingIdentity {
		if !actuallyExists {
			return fmt.Errorf("identity does not exist")
		}
	} else {
		if actuallyExists {
			return fmt.Errorf("identity already exists")
		}

		identityRecord := &Identity{
			Identity: identity,
		}

		if err := s.identityRepository.CreateVersion(ctx, identityRecord); err != nil {
			return err
		}
	}

	keysRecord := &AuthenticationKeys{
		Identity:     identity,
		Device:       device,
		PublicKey:    publicKey,
		RotationHash: rotationHash,
	}

	// a uniqueness constraint protects against a duplicated device id
	if err := s.authenticationKeysRepository.CreateVersion(ctx, keysRecord); err != nil {
		return err
	}

	if err := s.store.CommitTransaction(); err != nil {
		return err
	}

	committed = true

	return nil
}

func (s AuthenticationKeyStore) Rotate(ctx context.Context, identity, device, publicKey, rotationHash string) error {
	record := &AuthenticationKeys{}

	if err := s.authenticationKeysRepository.Get(
		ctx,
		record,
		clauses.And([]data.ClauseOrExpression{
			expressions.Equal("identity", identity),
			expressions.Equal("device", device),
		}),
		orderings.Descending("sequence_number"),
	); err != nil {
		return err
	}

	if record.Revoked {
		return fmt.Errorf("revoked device")
	}

	hash := s.hasher.Sum([]byte(publicKey))

	if !strings.EqualFold(hash, record.RotationHash) {
		return fmt.Errorf("rotation hash does not match")
	}

	record.PublicKey = publicKey
	record.RotationHash = rotationHash

	if err := s.authenticationKeysRepository.CreateVersion(ctx, record); err != nil {
		return err
	}

	return nil
}

func (s AuthenticationKeyStore) Public(ctx context.Context, identity, device string) (string, error) {
	record := &AuthenticationKeys{}

	if err := s.authenticationKeysRepository.Get(
		ctx,
		record,
		clauses.And([]data.ClauseOrExpression{
			expressions.Equal("identity", identity),
			expressions.Equal("device", device),
		}),
		orderings.Descending("sequence_number"),
	); err != nil {
		return "", err
	}

	if record.Revoked {
		return "", fmt.Errorf("revoked device")
	}

	return record.PublicKey, nil
}

func (s AuthenticationKeyStore) RevokeDevice(ctx context.Context, identity, device string) error {
	record := &AuthenticationKeys{}

	if err := s.authenticationKeysRepository.Get(
		ctx,
		record,
		clauses.And([]data.ClauseOrExpression{
			expressions.Equal("identity", identity),
			expressions.Equal("device", device),
		}),
		orderings.Descending("sequence_number"),
	); err != nil {
		return err
	}

	record.Revoked = true

	if err := s.authenticationKeysRepository.CreateVersion(ctx, record); err != nil {
		return err
	}

	return nil
}

func (s AuthenticationKeyStore) RevokeDevices(ctx context.Context, identity string) error {
	records := []*AuthenticationKeys{}

	if err := s.authenticationKeysRepository.ListLatestByPrefix(
		ctx,
		&records,
		expressions.Equal("identity", identity),
		expressions.NotEqual("revoked", true),
		nil,
		nil,
	); err != nil {
		return err
	}

	for _, record := range records {
		record.Revoked = true

		if err := s.authenticationKeysRepository.CreateVersion(ctx, record); err != nil {
			return err
		}
	}

	return nil
}

func (s AuthenticationKeyStore) DeleteIdentity(ctx context.Context, identity string) error {
	if err := s.RevokeDevices(ctx, identity); err != nil {
		return err
	}

	record := &Identity{}
	if err := s.identityRepository.Get(
		ctx,
		record,
		expressions.Equal("identity", identity),
		orderings.Descending("sequence_number"),
	); err != nil {
		return err
	}

	if !record.Deleted {
		record.Deleted = true
		if err := s.identityRepository.CreateVersion(ctx, record); err != nil {
			return err
		}
	}

	return nil
}
