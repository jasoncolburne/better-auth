package implementation

import (
	"github.com/jasoncolburne/better-auth-go/examples/crypto"
	"github.com/jasoncolburne/better-auth-go/pkg/cryptointerfaces"
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
