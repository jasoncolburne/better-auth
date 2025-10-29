#!/bin/bash
set -e

NAMESPACE="better-auth-basic-example-dev"

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
echo "Step 1/3: Rotating HSM key..."
./scripts/rotate-hsm-key.sh

echo ""
echo "Step 2/3: Flushing Redis databases..."
kubectl exec -n "$NAMESPACE" deployment/redis -- redis-cli -n 0 FLUSHDB
kubectl exec -n "$NAMESPACE" deployment/redis -- redis-cli -n 1 FLUSHDB

echo ""
echo "Step 3/3: Restarting services..."
kubectl rollout restart deployment/auth -n "$NAMESPACE"
kubectl rollout restart deployment/app-ts -n "$NAMESPACE"
kubectl rollout restart deployment/app-rb -n "$NAMESPACE"
kubectl rollout restart deployment/app-rs -n "$NAMESPACE"
kubectl rollout restart deployment/app-py -n "$NAMESPACE"

echo ""
echo "✓ Red button sequence complete!"
echo ""
echo "Services are restarting and will:"
echo "  - Generate new key pairs"
echo "  - Sign them with the rotated HSM key"
echo "  - Store them in Redis"
echo ""
echo "Wait ~30 seconds for all services to become ready."
