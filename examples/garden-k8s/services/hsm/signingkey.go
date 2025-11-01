package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"fmt"
	"log"
	"math/big"
	"sync"

	"github.com/miekg/pkcs11"
)

const (
	PKCS11_LIB  = "/usr/lib/softhsm/libsofthsm2.so"
	TOKEN_LABEL = "test-token"
	TOKEN_PIN   = "1234"
)

type SigningKey struct {
	identity      string
	generationId  string
	cesrPublicKey string

	ctx        *pkcs11.Ctx
	session    pkcs11.SessionHandle
	privateKey pkcs11.ObjectHandle

	mu sync.Mutex // Protects PKCS#11 operations from concurrent access
}

func NewSigningKey() (*SigningKey, error) {
	// Initialize PKCS#11
	ctx := pkcs11.New(PKCS11_LIB)
	if ctx == nil {
		return nil, fmt.Errorf("failed to load PKCS#11 library")
	}

	err := ctx.Initialize()
	if err != nil {
		return nil, fmt.Errorf("failed to initialize PKCS#11: %w", err)
	}

	// Find slot with token
	slots, err := ctx.GetSlotList(true)
	if err != nil {
		return nil, fmt.Errorf("failed to get slot list: %w", err)
	}

	if len(slots) == 0 {
		return nil, fmt.Errorf("no slots found")
	}

	slot := slots[0]

	// Open session
	session, err := ctx.OpenSession(slot, pkcs11.CKF_SERIAL_SESSION|pkcs11.CKF_RW_SESSION)
	if err != nil {
		return nil, fmt.Errorf("failed to open session: %w", err)
	}

	// Login
	err = ctx.Login(session, pkcs11.CKU_USER, TOKEN_PIN)
	if err != nil {
		return nil, fmt.Errorf("failed to login: %w", err)
	}

	return &SigningKey{
		ctx:     ctx,
		session: session,
	}, nil
}

func (k *SigningKey) generateKey(label string, id uint64) error {
	// Lock to prevent concurrent PKCS#11 operations
	// PKCS#11 sessions are not thread-safe and will segfault if used concurrently
	k.mu.Lock()
	defer k.mu.Unlock()

	// EC parameters for secp256r1 (P-256)
	ecParams := []byte{0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07}

	// Public key template
	publicKeyTemplate := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_CLASS, pkcs11.CKO_PUBLIC_KEY),
		pkcs11.NewAttribute(pkcs11.CKA_KEY_TYPE, pkcs11.CKK_EC),
		pkcs11.NewAttribute(pkcs11.CKA_LABEL, label),
		pkcs11.NewAttribute(pkcs11.CKA_ID, []byte(fmt.Sprintf("%08d", id))),
		pkcs11.NewAttribute(pkcs11.CKA_EC_PARAMS, ecParams),
		pkcs11.NewAttribute(pkcs11.CKA_VERIFY, true),
		pkcs11.NewAttribute(pkcs11.CKA_TOKEN, true),
	}

	// Private key template
	privateKeyTemplate := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_CLASS, pkcs11.CKO_PRIVATE_KEY),
		pkcs11.NewAttribute(pkcs11.CKA_KEY_TYPE, pkcs11.CKK_EC),
		pkcs11.NewAttribute(pkcs11.CKA_LABEL, label),
		pkcs11.NewAttribute(pkcs11.CKA_ID, []byte(fmt.Sprintf("%08d", id))),
		pkcs11.NewAttribute(pkcs11.CKA_SIGN, true),
		pkcs11.NewAttribute(pkcs11.CKA_TOKEN, true),
		pkcs11.NewAttribute(pkcs11.CKA_PRIVATE, true),
		pkcs11.NewAttribute(pkcs11.CKA_SENSITIVE, true),
	}

	// Generate key pair
	mechanism := []*pkcs11.Mechanism{pkcs11.NewMechanism(pkcs11.CKM_EC_KEY_PAIR_GEN, nil)}
	_, _, err := k.ctx.GenerateKeyPair(k.session, mechanism, publicKeyTemplate, privateKeyTemplate)
	if err != nil {
		return fmt.Errorf("failed to generate key pair: %w", err)
	}

	return nil
}

// publicKeyUnlocked is the internal version that doesn't acquire the mutex
func (k *SigningKey) publicKeyUnlocked(label string, id uint64) (string, error) {
	// Find public key to export
	publicKeyTemplate := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_CLASS, pkcs11.CKO_PUBLIC_KEY),
		pkcs11.NewAttribute(pkcs11.CKA_LABEL, label),
		pkcs11.NewAttribute(pkcs11.CKA_ID, []byte(fmt.Sprintf("%08d", id))),
	}

	err := k.ctx.FindObjectsInit(k.session, publicKeyTemplate)
	if err != nil {
		return "", fmt.Errorf("failed to init find public key: %w", err)
	}

	publicKeys, _, err := k.ctx.FindObjects(k.session, 1)
	if err != nil {
		return "", fmt.Errorf("failed to find public key: %w", err)
	}

	err = k.ctx.FindObjectsFinal(k.session)
	if err != nil {
		return "", fmt.Errorf("failed to finalize public key find: %w", err)
	}

	if len(publicKeys) == 0 {
		return "", fmt.Errorf("public key not found")
	}

	// Get EC_POINT from public key
	ecPointAttr := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_EC_POINT, nil),
	}

	attrs, err := k.ctx.GetAttributeValue(k.session, publicKeys[0], ecPointAttr)
	if err != nil {
		return "", fmt.Errorf("failed to get EC_POINT: %w", err)
	}

	// EC_POINT is DER-encoded OCTET STRING, skip DER wrapper (first 2-3 bytes)
	ecPoint := attrs[0].Value
	var publicKeyBytes []byte
	if len(ecPoint) > 0 && ecPoint[0] == 0x04 {
		// Skip OCTET STRING tag and length
		if ecPoint[1] == 0x41 { // length 65
			publicKeyBytes = ecPoint[2:]
		} else {
			publicKeyBytes = ecPoint
		}
	}

	if len(publicKeyBytes) != 65 || publicKeyBytes[0] != 0x04 {
		return "", fmt.Errorf("invalid EC_POINT format")
	}

	// Parse to ecdsa.PublicKey
	ecdsaPublicKey, err := ecdsa.ParseUncompressedPublicKey(elliptic.P256(), publicKeyBytes)
	if err != nil {
		return "", fmt.Errorf("failed to parse public key: %w", err)
	}

	cesrPublicKey, err := PublicKeyToCESR(ecdsaPublicKey)
	if err != nil {
		return "", fmt.Errorf("failed to convert public key to CESR")
	}

	return cesrPublicKey, nil
}

// publicKey is the public API that acquires the mutex
func (k *SigningKey) publicKey(label string, id uint64) (string, error) {
	k.mu.Lock()
	defer k.mu.Unlock()
	return k.publicKeyUnlocked(label, id)
}

func (k *SigningKey) loadKey(label string, id uint64) error {
	log.Printf("loadKey: attempting to load key with label=%s, id=%d", label, id)

	// Lock to prevent concurrent PKCS#11 operations
	// PKCS#11 sessions are not thread-safe and will segfault if used concurrently
	k.mu.Lock()
	defer k.mu.Unlock()

	log.Printf("loadKey: lock acquired, searching for private key...")

	// Find private key
	privateKeyTemplate := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_CLASS, pkcs11.CKO_PRIVATE_KEY),
		pkcs11.NewAttribute(pkcs11.CKA_LABEL, label),
		pkcs11.NewAttribute(pkcs11.CKA_ID, []byte(fmt.Sprintf("%08d", id))),
	}

	err := k.ctx.FindObjectsInit(k.session, privateKeyTemplate)
	if err != nil {
		log.Printf("loadKey: failed to init find objects: %v", err)
		return fmt.Errorf("failed to init find objects: %w", err)
	}

	privateKeys, _, err := k.ctx.FindObjects(k.session, 1)
	if err != nil {
		log.Printf("loadKey: failed to find private key: %v", err)
		return fmt.Errorf("failed to find private key: %w", err)
	}

	err = k.ctx.FindObjectsFinal(k.session)
	if err != nil {
		log.Printf("loadKey: failed to finalize find: %v", err)
		return fmt.Errorf("failed to finalize find: %w", err)
	}

	if len(privateKeys) == 0 {
		log.Printf("loadKey: private key not found with label=%s, id=%d", label, id)
		return fmt.Errorf("private key not found")
	}

	log.Printf("loadKey: private key found, loading public key...")
	cesrPublicKey, err := k.publicKeyUnlocked(label, id)
	if err != nil {
		log.Printf("loadKey: failed to load public key: %v", err)
		return err
	}

	k.privateKey = privateKeys[0]
	k.cesrPublicKey = cesrPublicKey

	log.Printf("loadKey: key loaded successfully")
	return nil
}

func (k *SigningKey) Close() {
	// Lock to prevent concurrent PKCS#11 operations
	// PKCS#11 sessions are not thread-safe and will segfault if used concurrently
	k.mu.Lock()
	defer k.mu.Unlock()

	if k.ctx != nil {
		k.ctx.Logout(k.session)
		k.ctx.CloseSession(k.session)
		k.ctx.Finalize()
		k.ctx.Destroy()
	}
}

func (k *SigningKey) Sign(data []byte) (string, error) {
	// Lock to prevent concurrent PKCS#11 operations
	// PKCS#11 sessions are not thread-safe and will segfault if used concurrently
	k.mu.Lock()
	defer k.mu.Unlock()

	// Hash the data
	hash := sha256.Sum256(data)

	// Sign with PKCS#11
	mechanism := []*pkcs11.Mechanism{pkcs11.NewMechanism(pkcs11.CKM_ECDSA, nil)}

	err := k.ctx.SignInit(k.session, mechanism, k.privateKey)
	if err != nil {
		return "", fmt.Errorf("failed to init signing: %w", err)
	}

	signature, err := k.ctx.Sign(k.session, hash[:])
	if err != nil {
		return "", fmt.Errorf("failed to sign: %w", err)
	}

	var r, sVal *big.Int

	// Try to parse as raw format first (64 bytes: 32 bytes R + 32 bytes S)
	if len(signature) == 64 {
		r = new(big.Int).SetBytes(signature[0:32])
		sVal = new(big.Int).SetBytes(signature[32:64])
	} else {
		// Try ASN.1 format
		r, sVal, err = ParseASN1Signature(signature)
		if err != nil {
			return "", fmt.Errorf("failed to parse signature (len=%d): %w", len(signature), err)
		}
	}

	// Convert to CESR
	cesrSignature, err := SignatureToCESR(r, sVal)
	if err != nil {
		return "", fmt.Errorf("failed to encode signature: %w", err)
	}

	return cesrSignature, nil
}
