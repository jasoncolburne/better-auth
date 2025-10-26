package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"os"
	"sync"

	"github.com/miekg/pkcs11"
)

const (
	PKCS11_LIB  = "/usr/lib/softhsm/libsofthsm2.so"
	TOKEN_LABEL = "test-token"
	TOKEN_PIN   = "1234"
	KEY_LABEL   = "authorization-key"
	KEY_ID      = "01"
)

type HSMServer struct {
	ctx           *pkcs11.Ctx
	session       pkcs11.SessionHandle
	privateKey    pkcs11.ObjectHandle
	cesrPublicKey string
	mu            sync.Mutex // Protects PKCS#11 operations from concurrent access
}

type SignRequest struct {
	Payload json.RawMessage `json:"payload"` // JSON payload to sign
}

type SignResponseBody struct {
	Payload     json.RawMessage `json:"payload"`     // JSON that was signed
	HsmIdentity string          `json:"hsmIdentity"` // identity of the HSM key
}

type SignResponse struct {
	Body      SignResponseBody `json:"body"`      // The data that was signed (as JSON)
	Signature string           `json:"signature"` // CESR-encoded signature
}

type PublicKeyResponse struct {
	PublicKey string `json:"publicKey"` // CESR-encoded public key
}

type ErrorResponse struct {
	Error string `json:"error"`
}

func NewHSMServer() (*HSMServer, error) {
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

	// Find private key
	privateKeyTemplate := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_CLASS, pkcs11.CKO_PRIVATE_KEY),
		pkcs11.NewAttribute(pkcs11.CKA_LABEL, KEY_LABEL),
	}

	err = ctx.FindObjectsInit(session, privateKeyTemplate)
	if err != nil {
		return nil, fmt.Errorf("failed to init find objects: %w", err)
	}

	privateKeys, _, err := ctx.FindObjects(session, 1)
	if err != nil {
		return nil, fmt.Errorf("failed to find private key: %w", err)
	}

	err = ctx.FindObjectsFinal(session)
	if err != nil {
		return nil, fmt.Errorf("failed to finalize find: %w", err)
	}

	if len(privateKeys) == 0 {
		return nil, fmt.Errorf("private key not found")
	}

	privateKey := privateKeys[0]

	// Find public key to export
	publicKeyTemplate := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_CLASS, pkcs11.CKO_PUBLIC_KEY),
		pkcs11.NewAttribute(pkcs11.CKA_LABEL, KEY_LABEL),
	}

	err = ctx.FindObjectsInit(session, publicKeyTemplate)
	if err != nil {
		return nil, fmt.Errorf("failed to init find public key: %w", err)
	}

	publicKeys, _, err := ctx.FindObjects(session, 1)
	if err != nil {
		return nil, fmt.Errorf("failed to find public key: %w", err)
	}

	err = ctx.FindObjectsFinal(session)
	if err != nil {
		return nil, fmt.Errorf("failed to finalize public key find: %w", err)
	}

	if len(publicKeys) == 0 {
		return nil, fmt.Errorf("public key not found")
	}

	// Get EC_POINT from public key
	ecPointAttr := []*pkcs11.Attribute{
		pkcs11.NewAttribute(pkcs11.CKA_EC_POINT, nil),
	}

	attrs, err := ctx.GetAttributeValue(session, publicKeys[0], ecPointAttr)
	if err != nil {
		return nil, fmt.Errorf("failed to get EC_POINT: %w", err)
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
		return nil, fmt.Errorf("invalid EC_POINT format")
	}

	// Parse to ecdsa.PublicKey
	ecdsaPublicKey, err := ecdsa.ParseUncompressedPublicKey(elliptic.P256(), publicKeyBytes)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key: %w", err)
	}

	cesrPublicKey, err := PublicKeyToCESR(ecdsaPublicKey)
	if err != nil {
		return nil, fmt.Errorf("failed to convert public key to CESR")
	}

	log.Printf("HSM initialized successfully")

	return &HSMServer{
		ctx:           ctx,
		session:       session,
		privateKey:    privateKey,
		cesrPublicKey: cesrPublicKey,
	}, nil
}

func (s *HSMServer) Close() {
	if s.ctx != nil {
		s.ctx.Logout(s.session)
		s.ctx.CloseSession(s.session)
		s.ctx.Finalize()
		s.ctx.Destroy()
	}
}

func (s *HSMServer) Sign(data []byte) (string, error) {
	// Lock to prevent concurrent PKCS#11 operations
	// PKCS#11 sessions are not thread-safe and will segfault if used concurrently
	s.mu.Lock()
	defer s.mu.Unlock()

	// Hash the data
	hash := sha256.Sum256(data)

	// Sign with PKCS#11
	mechanism := []*pkcs11.Mechanism{pkcs11.NewMechanism(pkcs11.CKM_ECDSA, nil)}

	err := s.ctx.SignInit(s.session, mechanism, s.privateKey)
	if err != nil {
		return "", fmt.Errorf("failed to init signing: %w", err)
	}

	signature, err := s.ctx.Sign(s.session, hash[:])
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

func (s *HSMServer) handleSign(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req SignRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "invalid request"})
		return
	}

	// Validate that payload is valid JSON
	if !json.Valid(req.Payload) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "invalid JSON payload"})
		return
	}

	// Construct the body (payload + hsmIdentity)
	body := SignResponseBody{
		Payload:     req.Payload,
		HsmIdentity: s.cesrPublicKey,
	}

	// Serialize the body to JSON for signing
	bodyJSON, err := json.Marshal(body)
	if err != nil {
		log.Printf("Failed to marshal body: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "failed to marshal body"})
		return
	}

	// Sign the body JSON
	signature, err := s.Sign(bodyJSON)
	if err != nil {
		log.Printf("Sign error: %v", err)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "signing failed"})
		return
	}

	// Return body and CESR signature
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(SignResponse{
		Body:      body,
		Signature: signature,
	})
}

func (s *HSMServer) handlePublicKey(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(PublicKeyResponse{PublicKey: s.cesrPublicKey})
}

func (s *HSMServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"status":"healthy"}`)
}

func main() {
	server, err := NewHSMServer()
	if err != nil {
		log.Fatalf("Failed to initialize HSM server: %v", err)
	}
	defer server.Close()

	// Log public key at startup
	log.Printf("HSM authorization public key (CESR): %s", server.cesrPublicKey)

	http.HandleFunc("/sign", server.handleSign)
	http.HandleFunc("/public-key", server.handlePublicKey)
	http.HandleFunc("/health", server.handleHealth)

	port := os.Getenv("PORT")
	if port == "" {
		port = "11111"
	}

	log.Printf("HSM server listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
