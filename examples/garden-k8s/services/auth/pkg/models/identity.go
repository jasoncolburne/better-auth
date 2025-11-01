package models

import "github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"

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
