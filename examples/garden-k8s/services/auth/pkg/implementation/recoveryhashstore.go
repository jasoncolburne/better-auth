package implementation

import (
	"context"
	"fmt"
	"strings"

	"github.com/jasoncolburne/better-auth/examples/garden-k8s/auth/pkg/models"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/expressions"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/data/orderings"
	"github.com/jasoncolburne/verifiable-storage-go/pkg/repository"
)

type RecoveryHashStore struct {
	recoveryHashRepository repository.Repository[*models.RecoveryHash]
}

func NewRecoveryHashStore(store data.Store) *RecoveryHashStore {
	recoveryHashRepository := repository.NewVerifiableRepository[*models.RecoveryHash](store, true, true, nil)
	return &RecoveryHashStore{
		recoveryHashRepository: recoveryHashRepository,
	}
}

func (s RecoveryHashStore) Register(ctx context.Context, identity, recoveryHash string) error {
	record := &models.RecoveryHash{
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
	record := &models.RecoveryHash{}
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
	record := &models.RecoveryHash{}
	if err := s.recoveryHashRepository.Get(ctx, record, expressions.Equal("identity", identity), orderings.Descending("sequence_number")); err != nil {
		return err
	}

	record.RecoveryHash = newHash

	if err := s.recoveryHashRepository.CreateVersion(ctx, record); err != nil {
		return err
	}

	return nil
}
