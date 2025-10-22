package db

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"

	"github.com/jasoncolburne/verifiable-storage-go/pkg/data"
	"github.com/jmoiron/sqlx"
	"github.com/lib/pq"
)

type PostgreSQLStore struct {
	db *sqlx.DB
	tx *sqlx.Tx
}

func NewPostgreSQLStore(ctx context.Context, dsn string, migrations []string) (*PostgreSQLStore, error) {
	db, err := sqlx.Connect("postgres", dsn)
	if err != nil {
		return nil, err
	}

	for _, migration := range migrations {
		if _, err := db.ExecContext(ctx, migration); err != nil {
			db.Close()
			return nil, err
		}
	}

	return &PostgreSQLStore{
		db: db.Unsafe(), // the unsafe here allows us to gracefully ignore computed columns
		tx: nil,
	}, nil
}

func (s PostgreSQLStore) Sql() data.SQLStore {
	if s.tx == nil {
		return s.db
	} else {
		return s.tx
	}
}

func (s *PostgreSQLStore) BeginTransaction(ctx context.Context, opts *sql.TxOptions) error {
	if s.tx != nil {
		return fmt.Errorf("transaction in progress")
	}

	var err error
	s.tx, err = s.db.BeginTxx(ctx, opts)
	if err != nil {
		s.tx = nil
		return err
	}

	return nil
}

func (s *PostgreSQLStore) CommitTransaction() error {
	if s.tx == nil {
		return fmt.Errorf("no transaction in progress")
	}

	if err := s.tx.Commit(); err != nil {
		return err
	}

	s.tx = nil

	return nil
}

func (s *PostgreSQLStore) RollbackTransaction() error {
	if s.tx == nil {
		return fmt.Errorf("no transaction in progress")
	}

	if err := s.tx.Rollback(); err != nil {
		return err
	}

	s.tx = nil

	return nil
}

func (*PostgreSQLStore) ReplacePlaceholders(query string) string {
	count := 0
	return regexp.MustCompile(`\?`).ReplaceAllStringFunc(query, func(m string) string {
		count++
		return fmt.Sprintf("$%d", count)
	})
}

type AnyBuilder struct{}

func NewAnyBuilder() *AnyBuilder {
	return &AnyBuilder{}
}

func (AnyBuilder) String(column string, values []any) string {
	expression := fmt.Sprintf("%s=ANY(?)", column)
	return expression
}

func (AnyBuilder) Values(values []any) []any {
	return []any{pq.Array(values)}
}
