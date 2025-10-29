#!/bin/bash
set -e

echo "=========================================="
echo "🚨 RED BUTTON: Emergency Key Rotation 🚨"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Rotate the HSM signing key"
echo "  2. Flush Redis DBs 0 (access keys) and 1 (response keys)"
echo "  3. Restart auth and all app services"
echo ""
echo "Preserved:"
echo "  - DB 2 (access key hashes)"
echo "  - DB 3 (revoked devices)"
echo "  - DB 4 (HSM keys)"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=========================================="
echo "Step 1/2: Rotating HSM key..."
echo "=========================================="
./scripts/rotate-hsm-key.sh

echo ""
echo "=========================================="
echo "Step 2/2: Purging keys and rolling services..."
echo "=========================================="
# Skip the confirmation prompt since we already confirmed
export SKIP_CONFIRM=1
./scripts/purge-keys-and-roll-services.sh

echo ""
echo "=========================================="
echo "✓ Red button sequence complete!"
echo "=========================================="
echo ""
echo "All services have been rotated with new keys signed by the rotated HSM key."
