package models

import "github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"

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
