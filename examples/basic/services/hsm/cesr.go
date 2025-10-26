package main

import (
	"crypto/ecdsa"
	"encoding/asn1"
	"encoding/base64"
	"fmt"
	"math/big"
)

// CESR encoding utilities copied from better-auth-go
// This file provides standalone CESR encoding for the HSM service

// compressPublicKey compresses an uncompressed ECDSA P-256 public key
func compressPublicKey(pubKeyBytes []byte) ([]byte, error) {
	if len(pubKeyBytes) != 65 {
		return nil, fmt.Errorf("invalid public key length: expected 65, got %d", len(pubKeyBytes))
	}

	if pubKeyBytes[0] != 0x04 {
		return nil, fmt.Errorf("invalid public key header: expected 0x04, got 0x%02x", pubKeyBytes[0])
	}

	x := pubKeyBytes[1:33]
	y := pubKeyBytes[33:65]

	// Determine parity of y coordinate
	yParity := y[31] & 0x01
	var prefix byte
	if yParity == 0 {
		prefix = 0x02
	} else {
		prefix = 0x03
	}

	compressed := make([]byte, 33)
	compressed[0] = prefix
	copy(compressed[1:], x)

	return compressed, nil
}

// PublicKeyToCESR converts an ECDSA P-256 public key to CESR format
// Returns string in format "1AAI<base64-compressed-public-key>"
func PublicKeyToCESR(publicKey *ecdsa.PublicKey) (string, error) {
	// Get uncompressed public key bytes using PublicKey.Bytes()
	publicKeyBytes, err := publicKey.Bytes()
	if err != nil {
		return "", fmt.Errorf("failed to get public key bytes: %w", err)
	}

	// Compress the public key
	compressedKey, err := compressPublicKey(publicKeyBytes)
	if err != nil {
		return "", fmt.Errorf("failed to compress public key: %w", err)
	}

	// Encode to CESR format: "1AAI" + base64
	base64PublicKey := base64.URLEncoding.EncodeToString(compressedKey)
	cesrPublicKey := fmt.Sprintf("1AAI%s", base64PublicKey)

	return cesrPublicKey, nil
}

// SignatureToCESR converts an ECDSA signature (R, S) to CESR format
// Returns string with signature starting with "0I"
func SignatureToCESR(r, s *big.Int) (string, error) {
	// Create 66-byte signature: 2 zero bytes + 32 bytes R + 32 bytes S
	// Use FillBytes to properly handle big.Int to fixed-size byte arrays
	signatureBytes := make([]byte, 66)
	r.FillBytes(signatureBytes[2:34])
	s.FillBytes(signatureBytes[34:66])

	// Base64 encode
	base64Signature := base64.URLEncoding.EncodeToString(signatureBytes)

	// Replace first two characters with "0I" for CESR format
	runes := []rune(base64Signature)
	runes[0] = '0'
	runes[1] = 'I'

	return string(runes), nil
}

// ParseASN1Signature parses an ASN.1 DER encoded ECDSA signature
// Returns R and S components
func ParseASN1Signature(asn1Sig []byte) (*big.Int, *big.Int, error) {
	type ecdsaSignature struct {
		R, S *big.Int
	}

	var sig ecdsaSignature
	_, err := asn1.Unmarshal(asn1Sig, &sig)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to unmarshal ASN.1 signature: %w", err)
	}

	return sig.R, sig.S, nil
}
