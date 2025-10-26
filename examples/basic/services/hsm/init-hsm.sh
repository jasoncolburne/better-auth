#!/bin/bash
set -e

TOKEN_LABEL="test-token"
SO_PIN="5678"
USER_PIN="1234"
KEY_LABEL="authorization-key"
KEY_ID="01"
PRIVATE_KEY_FILE="/keys/hsm-authorization-key.pem"

echo "Initializing SoftHSM2 token..."

# Initialize token
softhsm2-util --init-token --slot 0 --label "$TOKEN_LABEL" --so-pin "$SO_PIN" --pin "$USER_PIN"

echo "Token initialized successfully"

# Get the actual slot number assigned to the token
SLOT=$(softhsm2-util --show-slots | grep "Slot " | head -1 | awk '{print $2}')

echo "Using slot $SLOT"

# Check if private key file exists for import
if [ -f "$PRIVATE_KEY_FILE" ]; then
    echo "Found existing private key, importing..."

    # Convert to PKCS#8 format for SoftHSM2 import
    openssl pkcs8 -topk8 -nocrypt -in "$PRIVATE_KEY_FILE" -out /tmp/import_key.pem

    # Import the PKCS#8 key
    softhsm2-util --import /tmp/import_key.pem \
        --slot "$SLOT" \
        --label "$KEY_LABEL" \
        --id "$KEY_ID" \
        --pin "$USER_PIN"

    # Cleanup
    rm -f /tmp/import_key.pem

    echo "Private key imported successfully"
else
    echo "No existing private key found, generating new key with openssl..."

    # Generate EC private key with openssl in traditional format
    openssl ecparam -genkey -name prime256v1 -noout -out /tmp/newkey_ec.pem

    # Convert to PKCS#8 format for SoftHSM2
    openssl pkcs8 -topk8 -nocrypt -in /tmp/newkey_ec.pem -out /tmp/newkey.pem

    # Save traditional format to persistent location for later export
    mkdir -p /keys
    cp /tmp/newkey_ec.pem "$PRIVATE_KEY_FILE"

    # Import the PKCS#8 key into HSM
    softhsm2-util --import /tmp/newkey.pem \
        --slot "$SLOT" \
        --label "$KEY_LABEL" \
        --id "$KEY_ID" \
        --pin "$USER_PIN"

    # Cleanup temporary files
    rm -f /tmp/newkey.pem /tmp/newkey_ec.pem

    echo "Key pair generated and imported successfully"
fi

echo "HSM initialization complete"
