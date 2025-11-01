#!/bin/bash
set -e

NAMESPACE="better-auth-basic-example-dev"

echo "================================================"
echo "🔄 Purge Keys and Roll Services"
echo "================================================"
echo ""
echo "This will:"
echo "  1. Flush Redis DBs 0 (access keys) and 1 (response keys)"
echo "  2. Restart auth and all app services"
echo ""
echo "Use case: Service key compromise (without HSM key compromise)"
echo ""

if [ "$SKIP_CONFIRM" != "1" ]; then
  read -p "Are you sure you want to proceed? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 0
  fi
fi

echo ""
echo "Step 1/2: Flushing Redis databases..."
kubectl exec -n "$NAMESPACE" deployment/redis -- redis-cli -n 0 FLUSHDB
kubectl exec -n "$NAMESPACE" deployment/redis -- redis-cli -n 1 FLUSHDB

echo ""
echo "Step 2/2: Restarting services..."
kubectl rollout restart deployment/auth -n "$NAMESPACE"
kubectl rollout restart deployment/app-ts -n "$NAMESPACE"
kubectl rollout restart deployment/app-rb -n "$NAMESPACE"
kubectl rollout restart deployment/app-rs -n "$NAMESPACE"
kubectl rollout restart deployment/app-py -n "$NAMESPACE"

echo ""
echo "✓ Key purge and service rollout complete!"
echo ""
echo "Services are restarting and will:"
echo "  - Generate new key pairs"
echo "  - Sign them with the existing HSM key"
echo "  - Store them in Redis"
echo ""
echo "Wait ~30 seconds for all services to become ready."
