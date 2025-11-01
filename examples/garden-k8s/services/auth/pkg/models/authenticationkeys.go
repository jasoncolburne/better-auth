package models

import "github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"

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
