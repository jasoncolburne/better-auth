#!/bin/bash
set -e

# Export HSM identity from the keys service
# This script fetches the HSM identity and saves it to test-fixtures/hsm.id

KEYS_URL="http://keys.better-auth.local/hsm/keys"
OUTPUT_FILE="test-fixtures/hsm.id"

echo "Fetching HSM identity from ${KEYS_URL}..."

# Fetch and extract the prefix field from the object with sequenceNumber 0
# -r: raw output (no quotes)
HSM_ID=$(curl -s "${KEYS_URL}" | jq -r '.[] | select(.payload.sequenceNumber == 0) | .payload.prefix')

if [ -z "$HSM_ID" ] || [ "$HSM_ID" = "null" ]; then
  echo "Error: Failed to fetch HSM identity from ${KEYS_URL}"
  echo "Make sure the HSM and keys services are deployed and accessible."
  exit 1
fi

# Save to file
echo -n "$HSM_ID" > "$OUTPUT_FILE"

echo "HSM identity exported successfully to ${OUTPUT_FILE}"
echo "HSM ID: ${HSM_ID}"
