package implementation

import (
	"context"
	"fmt"
	"strings"

	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/jasoncolburne/better-auth/examples/basic/auth/pkg/models"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/clauses"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/expressions"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/orderings"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/repository"
)

type AuthenticationKeyStore struct {
	store  data.Store
	hasher cryptointerfaces.Hasher

	identityRepository           repository.Repository[*models.Identity]
	authenticationKeysRepository repository.Repository[*models.AuthenticationKeys]
}

func NewAuthenticationKeyStore(store data.Store) (*AuthenticationKeyStore, error) {
	hasher := crypto.NewBlake3()

	identityRepository := repository.NewVerifiableRepository[*models.Identity](
		store,
		true,
		true,
		nil, // nil for determinism
	)

	authenticationKeysRepository := repository.NewVerifiableRepository[*models.AuthenticationKeys](
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
	buffer := []*models.Identity{}

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

		identityRecord := &models.Identity{
			Identity: identity,
		}

		if err := s.identityRepository.CreateVersion(ctx, identityRecord); err != nil {
			return err
		}
	}

	keysRecord := &models.AuthenticationKeys{
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
	record := &models.AuthenticationKeys{}

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
	record := &models.AuthenticationKeys{}

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
	record := &models.AuthenticationKeys{}

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
	records := []*models.AuthenticationKeys{}

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

	record := &models.Identity{}
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

func (s AuthenticationKeyStore) EnsureActive(ctx context.Context, identity, device string) error {
	identityRecord := &models.Identity{}
	if err := s.identityRepository.Get(
		ctx,
		identityRecord,
		expressions.Equal("identity", identity),
		orderings.Descending("sequence_number"),
	); err != nil {
		return err
	}

	if identityRecord.Deleted {
		return fmt.Errorf("identity deleted")
	}

	keysRecord := &models.AuthenticationKeys{}

	if err := s.authenticationKeysRepository.Get(
		ctx,
		keysRecord,
		clauses.And([]data.ClauseOrExpression{
			expressions.Equal("identity", identity),
			expressions.Equal("device", device),
		}),
		orderings.Descending("sequence_number"),
	); err != nil {
		return err
	}

	if keysRecord.Revoked {
		return fmt.Errorf("device revoked")
	}

	return nil
}
