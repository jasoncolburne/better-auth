package implementation

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
	"github.com/jasoncolburne/better-auth/examples/garden-k8s/auth/pkg/models"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/expressions"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/orderings"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/repository"
)

type AuthenticationNonceStore struct {
	lifetime                      time.Duration
	noncer                        cryptointerfaces.Noncer
	identityRepository            repository.Repository[*models.Identity]
	authenticationNonceRepository repository.Repository[*models.AuthenticationNonce]
}

func NewAuthenticationNonceStore(store data.Store, lifetime time.Duration) *AuthenticationNonceStore {
	noncer := crypto.NewNoncer()

	// a better pattern would be injection of these repos
	identityRepository := repository.NewVerifiableRepository[*models.Identity](
		store,
		true,
		true,
		nil, // nil for determinism
	)

	authenticationNonceRepository := repository.NewVerifiableRepository[*models.AuthenticationNonce](
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
	identityRecord := &models.Identity{}
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

	record := &models.AuthenticationNonce{
		Identity:       identity,
		ChallengeNonce: nonce,
	}

	if err := s.authenticationNonceRepository.CreateVersion(ctx, record); err != nil {
		return "", err
	}

	return nonce, nil
}

func (s AuthenticationNonceStore) Verify(ctx context.Context, nonce string) (string, error) {
	record := &models.AuthenticationNonce{}
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
