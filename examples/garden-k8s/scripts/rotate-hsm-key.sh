#!/bin/bash
set -e

NAMESPACE="better-auth-basic-example-dev"
HSM_URL="http://localhost:11111/rotate"

echo "Triggering HSM key rotation..."

# Execute curl from inside the HSM pod itself
RESPONSE=$(kubectl exec -n "$NAMESPACE" deployment/hsm -- curl -s "$HSM_URL")

if [ -z "$RESPONSE" ]; then
  echo "Error: No response from HSM rotate endpoint"
  exit 1
fi

# Extract and display the new public key
NEW_KEY=$(echo "$RESPONSE" | jq -r '.newPublicKey')

if [ -z "$NEW_KEY" ] || [ "$NEW_KEY" = "null" ]; then
  echo "Error: Failed to parse rotation response"
  echo "Response: ${RESPONSE}"
  exit 1
fi

echo "✓ HSM key rotated successfully!"
echo "New Public Key: ${NEW_KEY}"
echo ""
echo "Note: Services will automatically pick up the new key on their next HSM request."
echo "      The HSM identity (prefix) remains the same - no need to re-export hsm.id"
