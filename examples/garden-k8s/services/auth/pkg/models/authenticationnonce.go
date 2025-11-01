package models

import "github.com/jasoncolburne/verifiable-storage-go/pkg/primitives"

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
