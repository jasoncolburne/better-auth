package main

import "github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"

// this table omits a nonce for more determinism
const KEYS_TABLE_SQL = `
	CREATE TABLE IF NOT EXISTS keys (
		-- Standard fields
		id              	TEXT PRIMARY KEY,
		prefix				TEXT NOT NULL,
		previous        	TEXT,
		sequence_number 	BIGINT NOT NULL,

		-- Optional fields
		created_at          TIMESTAMP NOT NULL,

		-- Model-specific fields
		purpose             TEXT NOT NULL,
		public_key			TEXT NOT NULL,
		rotation_hash       TEXT NOT NULL,

		-- Uniqueness constraint for sequence numbers
		UNIQUE(prefix, sequence_number)
	);
`

type Keys struct {
	primitives.VerifiableRecorder
	Purpose      string `db:"purpose" json:"purpose"`
	PublicKey    string `db:"public_key" json:"publicKey"`
	RotationHash string `db:"rotation_hash" json:"rotationHash"`
}

func (*Keys) TableName() string {
	return "keys"
}
