#!/bin/bash
set -e

PRIVATE_KEY_FILE="/keys/hsm-authorization-key.pem"

echo "Exporting private key from HSM..." >&2

# Output the private key that was saved during initialization
if [ -f "$PRIVATE_KEY_FILE" ]; then
    cat "$PRIVATE_KEY_FILE"
    echo "Private key exported successfully" >&2
else
    echo "Error: Private key file not found at $PRIVATE_KEY_FILE" >&2
    exit 1
fi
