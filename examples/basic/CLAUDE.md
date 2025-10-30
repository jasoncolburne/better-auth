# Better Auth Basic Example - Development Guide

This guide is for developers working on the Better Auth basic Kubernetes example. For user-facing documentation, see [README.md](./README.md).

## Quick Start for Development

```bash
# From examples/basic/
garden deploy --log-level=verbose

# Watch logs from all services
garden logs --follow
```

**IMPORTANT**: Always use `--log-level=verbose` with Garden build and deploy commands. The logs
written to `.garden/` are rarely valuable for debugging. Verbose output gives you real-time
feedback on what Garden is doing.

### HSM Identity Setup

After deploying HSM and keys services for the first time, export the HSM identity:

```bash
# Deploy HSM and keys services first
garden deploy hsm keys --log-level=verbose

# Export HSM identity to test-fixtures/hsm.id
./scripts/export-hsm-identity.sh
```

The HSM identity is required by auth and app services to verify the chain of trust for keys published by the keys service. The exported identity is stored in `test-fixtures/hsm.id` (gitignored) and should be injected into service code at build time.

**When to re-export:**
- After initial HSM deployment
- Before building/deploying auth or app services if `test-fixtures/hsm.id` doesn't exist

**Note:** The HSM identity (prefix) does not change during key rotation, so you only need to export it once per deployment environment.

## Development Workflow

### Making Changes to a Service

1. **Edit service code** in `services/<service-name>/`
2. **Rebuild and redeploy** with verbose output:
   ```bash
   garden deploy <service-name> --log-level=verbose
   ```
3. **Watch logs** to verify changes:
   ```bash
   garden logs <service-name> --follow
   ```

### Example: Modifying the TypeScript App Service

```bash
# Edit the service
vim services/app-ts/src/server.ts

# Rebuild and redeploy with verbose output
garden deploy app-ts --log-level=verbose

# Watch logs to see your changes
garden logs app-ts --follow

# Test the endpoint
curl -X POST -d '...' http://app-ts.better-auth.local/foo/bar
```

## Garden CLI Best Practices

### Always Use Verbose Logging

Garden's default output hides important information. **Always add `--log-level=verbose`**:

```bash
# Good - you'll see what's actually happening
garden deploy --log-level=verbose
garden build auth --log-level=verbose
garden logs app-ts --follow

# Bad - you'll miss important build/deploy information
garden deploy
garden build auth
```

The `.garden/` directory contains logs, but they often don't contain the information you need. Verbose console output is much more useful.

### Understanding Garden's Caching

Garden aggressively caches builds. Sometimes this causes stale builds:

```bash
# Force a clean rebuild
garden deploy <service> --force --log-level=verbose

# Force rebuild all services
garden deploy --force --log-level=verbose

# Clear Garden's cache entirely (nuclear option)
garden util mutagen reset
```

### Essential Garden Commands

```bash
# Deploy all services with verbose output
garden deploy --log-level=verbose

# Deploy specific service
garden deploy auth --log-level=verbose

# Build without deploying (useful for testing Dockerfiles)
garden build auth --log-level=verbose

# View logs from all services
garden logs --follow

# View logs from specific service
garden logs auth --follow

# Get deployment status
garden get status

# Run a specific task (like export-hsm-public-key)
garden run export-hsm-public-key --log-level=verbose

# Delete all deployments
garden delete deploy --log-level=verbose
```

## Local Library Development

When developing Better Auth libraries and testing them in this example:

### The Setup

For the most part, services reference local implementations via symlinks in `services/dependencies/`:
```
services/dependencies/
├── better-auth-ts -> ../../../../implementations/better-auth-ts
├── better-auth-rb -> ../../../../implementations/better-auth-rb
├── better-auth-rs -> ../../../../implementations/better-auth-rs
├── better-auth-py -> ../../../../implementations/better-auth-py
└── better-auth-go -> ../../../../implementations/better-auth-go
```

Each service's Dockerfile copies the library from the symlink:
```dockerfile
# TypeScript example
COPY services/dependencies/better-auth-ts /better-auth-ts
```

### Workflow for Library Changes

1. **Make changes to library** in `implementations/better-auth-ts/` (or any other)
2. **Rebuild dependent services** (Garden should detect file changes):
   ```bash
   garden deploy app-ts --log-level=verbose
   ```
3. **If Garden doesn't detect changes**, force rebuild:
   ```bash
   garden deploy app-ts --force --log-level=verbose
   ```

### Testing Library Changes Across Multiple Services

```bash
# Make changes to better-auth-ts library
vim ../../../implementations/better-auth-ts/src/access.ts

# Rebuild all TypeScript services
garden deploy app-ts --force --log-level=verbose

# Run integration tests from the library
cd ../../../implementations/better-auth-ts
npm run test:k8s
```

## Debugging Guide

### Garden Logs (Console Output)

```bash
# Follow all logs
garden logs --follow

# Follow specific service logs
garden logs auth --follow

# View recent logs without following
garden logs auth --tail 100

# View logs from multiple services
garden logs auth app-ts keys --follow
```

### Kubernetes Direct Debugging

When Garden's logging isn't enough, use kubectl directly:

```bash
# Get pod status
kubectl get pods -n better-auth-basic-example-dev

# View pod logs
kubectl logs -n better-auth-basic-example-dev deployment/auth --tail=100 -f

# Describe pod (shows events, errors, resource issues)
kubectl describe pod -n better-auth-basic-example-dev <pod-name>

# Shell into running container
kubectl exec -it -n better-auth-basic-example-dev deployment/auth -- sh

# Port forward to service (bypass ingress)
kubectl port-forward -n better-auth-basic-example-dev svc/auth 8080:80
# Then: curl http://localhost:8080/health
```

### Debugging Redis State

Redis uses persistent storage (256Mi PersistentVolumeClaim with AOF enabled), so data survives pod restarts and redeployments.

```bash
# Shell into Redis
kubectl exec -it -n better-auth-basic-example-dev deployment/redis -- redis-cli

# Inside redis-cli:
# SELECT 0  # Access keys
# KEYS *
# GET <key>
# SELECT 1  # Response keys
# KEYS *
# SELECT 2  # Access key hashes
# KEYS *

# Check persistence status
# INFO persistence

# Force a save
# SAVE
```

**Clearing Persistent Data**:

If you need to start fresh, you have two options:

```bash
# Option 1: Flush data from within Redis (keeps PVC)
kubectl exec -it -n better-auth-basic-example-dev deployment/redis -- redis-cli FLUSHALL

# Option 2: Delete the PVC (data is permanently lost)
garden delete deploy --log-level=verbose
kubectl delete pvc redis-data -n better-auth-basic-example-dev
garden deploy --log-level=verbose  # Creates new PVC
```

**Note**: The PVC survives `garden delete deploy` - you must manually delete it if you want to start completely fresh.

### Debugging Postgres State

Postgres also uses persistent storage (1Gi PersistentVolumeClaim), so database contents survive pod restarts and redeployments.

```bash
# Shell into Postgres
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -d better_auth

# Inside psql:
# \dt              # List tables
# \d accounts      # Describe accounts table
# SELECT * FROM accounts;
# SELECT * FROM devices;
# \q               # Quit
```

**Clearing Persistent Database**:

If you need to reset the database:

```bash
# Option 1: Drop and recreate database (from within postgres)
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres
# Inside psql:
DROP DATABASE better_auth;
CREATE DATABASE better_auth;
# Restart auth service to recreate tables
kubectl rollout restart deployment/auth -n better-auth-basic-example-dev

# Option 2: Delete the PVC (data is permanently lost)
garden delete deploy --log-level=verbose
kubectl delete pvc postgres-data -n better-auth-basic-example-dev
garden deploy --log-level=verbose  # Creates new PVC
```

**Note**: Like Redis, the Postgres PVC survives `garden delete deploy` - you must manually delete it if you want to start completely fresh.

### Debugging Build Failures

```bash
# Build with verbose output to see Docker build logs
garden build auth --log-level=verbose --force

# If Docker build fails, try building locally
cd services/auth
docker build -t test-auth .

# Check Garden's build cache
ls -la .garden/build/
```

### Debugging Network Issues

```bash
# Check ingress configuration
kubectl get ingress -n better-auth-basic-example-dev

# Test service-to-service communication
kubectl exec -it -n better-auth-basic-example-dev deployment/app-ts -- sh
# Inside container:
curl http://redis:6379
curl http://hsm:80/health

# Check /etc/hosts has ingress entries
cat /etc/hosts | grep better-auth
```

## Testing Strategy

### Integration Tests

The TypeScript implementation has comprehensive integration tests:

```bash
# From implementations/better-auth-ts/
npm run test:k8s
```

These tests verify:
- Full authentication flow (account creation, device linking, session management)
- All app service implementations (TypeScript, Ruby, Rust, Python)
- Token refresh and rotation
- Access request verification
- HSM key signing and verification

### Manual Testing

```bash
# Test health endpoints
curl http://auth.better-auth.local/health
curl http://app-ts.better-auth.local/health
curl http://keys.better-auth.local/keys

# Test access request (will fail without valid token, but shows error handling)
curl -X POST -d '{"payload":{"access":{"nonce":"test"}}}' \
  http://app-ts.better-auth.local/foo/bar
```

## Architecture Deep Dive

### Service Startup Sequence

1. **Redis** starts first (no dependencies)
2. **HSM** starts, generates/loads key pair, provides `/sign` endpoint
3. **Auth** starts, generates keys, signs with HSM, stores in Redis DB 0 & 1
4. **App services** start, generate response keys, sign with HSM, store in Redis DB 1
5. **Keys service** starts, reads from Redis DB 1, serves signed keys

### Redis Database Layout

- **DB 0**: Access keys (auth service writes, app services read)
  - Format: `access:<identity>` → HSM-signed access key
- **DB 1**: Response keys (all services write, clients read via keys service)
  - Format: `response:<identity>` → HSM-signed response key
- **DB 2**: Access key hashes (for refresh prevention)
  - Format: `accessKeyHash:<hash>` → "1" (exists if key already refreshed)

### HSM Key Signing Flow

```
Service Startup:
  1. Service generates key pair (access or response)
  2. Service creates payload: {purpose, publicKey, expiration}
  3. Service POSTs to HSM: POST http://hsm:80/sign
  4. HSM signs payload, returns: {body: {payload, hsmIdentity}, signature}
  5. Service stores entire HSM response in Redis

On Access Request:
  1. App service fetches key from Redis
  2. App verifies HSM signature using hardcoded HSM public key
  3. App extracts public key from payload
  4. App uses public key to verify client request
```

### CronJob Rolling Restarts

Every 12 hours, CronJobs trigger rolling restarts:
- Keys expire after 12 hours
- Rolling restart regenerates keys before expiration
- Zero downtime (Kubernetes graceful shutdown)
- Only failed jobs visible in `kubectl get jobs` (successful jobs cleaned immediately)

## Adding New Services

### Adding a New App Service (Example: Java)

1. **Create service directory**:
   ```bash
   mkdir -p services/app-java
   ```

2. **Create Dockerfile** (`services/app-java/Dockerfile`):
   ```dockerfile
   FROM openjdk:17-slim
   WORKDIR /app
   # Copy dependencies, build, etc.
   CMD ["java", "-jar", "app.jar"]
   ```

3. **Create Garden config** (`services/app-java/garden.yml`):
   ```yaml
   kind: Build
   name: app-java
   type: container
   spec:
     buildArgs: {}
   ---
   kind: Deploy
   name: app-java
   type: kubernetes
   dependencies: [build.app-java, deploy.redis, deploy.hsm]
   spec:
     defaultTarget:
       kind: Deployment
       name: app-java
     files:
       - manifests.yml.tpl
   ```

4. **Create Kubernetes manifests** (`services/app-java/manifests.yml.tpl`):
   - Use `services/app-ts/manifests.yml.tpl` as template
   - Update names, labels, and environment variables

5. **Implement service** using `better-auth-java` library (if it exists)

6. **Deploy**:
   ```bash
   garden deploy app-java --log-level=verbose
   ```

7. **Test**:
   ```bash
   curl -X POST -d '...' http://app-java.better-auth.local/foo/bar
   ```

## Common Development Tasks

### Nuclear Reset (Complete Fresh Start)

The cleanest way to reset everything including HSM identity, PVCs, and all state:

```bash
# Delete everything, redeploy HSM/keys, export identity, deploy all
garden delete deploy && garden deploy hsm keys && ./scripts/export-hsm-identity.sh && garden deploy
```

This is the recommended approach when:
- You want to start completely fresh
- Troubleshooting complex multi-service state issues
- Testing a clean deployment from scratch
- Need new HSM keys and identity

### Resetting Redis State

Redis data is now persistent (survives pod restarts and redeployments). To reset:

```bash
# Option 1: Flush data (quick, keeps PVC) - hsm service needs to be modified to re-export its keys for this to be a real option
kubectl exec -it -n better-auth-basic-example-dev deployment/redis -- redis-cli FLUSHALL

# Option 2: Flush specific database
kubectl exec -it -n better-auth-basic-example-dev deployment/redis -- redis-cli
# Inside redis-cli:
SELECT 0
FLUSHDB

# Option 3: Delete PVC and start completely fresh
kubectx delete deployment redis -n better-auth-basic-example-dev
kubectl delete pvc redis-data -n better-auth-basic-example-dev
garden deploy --log-level=verbose

# Option 4: Nuclear reset (regenerates HSM identity too)
garden delete deploy && garden deploy hsm keys && ./scripts/export-hsm-identity.sh && garden deploy
```

### Resetting Postgres State

Postgres data is now persistent (survives pod restarts and redeployments). To reset:

```bash
# Option 1: Drop and recreate database (quick, keeps PVC)
kubectl delete deployment hsm auth
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -c "DROP DATABASE better_auth_auth;"
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -c "DROP DATABASE better_auth_hsm;"
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -c "CREATE DATABASE better_auth_auth;"
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -c "CREATE DATABASE better_auth_hsm;"
garden deploy --log-level=verbose

# Option 2: Delete PVC and start completely fresh
kubectxl delete deployment postgres
kubectl delete pvc postgres-data -n better-auth-basic-example-dev
garden deploy --log-level=verbose

# Option 3: Nuclear reset (regenerates HSM identity too)
garden delete deploy && garden deploy hsm keys && ./scripts/export-hsm-identity.sh && garden deploy
```

### Rotating HSM Keys Manually

To manually rotate the HSM signing key without restarting anything:

```bash
./scripts/rotate-hsm-key.sh
```

This triggers HSM key rotation and displays the new public key. Services will automatically pick up the new key on their next HSM interaction. The HSM identity (prefix) remains unchanged, so you don't need to re-export `hsm.id` or rebuild services.

**When to use:**
- Testing key rotation logic
- Manual key rotation as part of planned rotation

**Note**: This rotates the signing key within the existing HSM key chain. The HSM identity (prefix) stays the same. All rotation is currently manual.

### Service Key Purge and Rollout

If a service key (not HSM key) is suspected to be compromised:

```bash
./scripts/purge-keys-and-roll-services.sh
```

This script purges all service-generated keys and restarts services to regenerate them:
1. Flushes Redis DB 0 (access keys) and DB 1 (response keys)
2. Restarts auth and all app services

**When to use:**
- Service key compromise (auth or app service key leaked)
- HSM key is known to be secure
- Testing service key regeneration without HSM rotation

**What happens:**
- All existing tokens become invalid immediately
- Services restart and generate new keys signed with the existing HSM key
- Clients must re-authenticate
- Takes ~30 seconds for services to become ready

**What's preserved:**
- HSM signing key (no rotation)
- Redis DB 2 (access key hashes), DB 3 (revoked devices), DB 4 (HSM keys)
- User accounts and devices in Postgres

### Emergency Key Rotation (Red Button)

For emergency situations requiring immediate key rotation and service restart:

```bash
./scripts/red-button.sh
```

This script performs a complete emergency rotation sequence:
1. Rotates the HSM signing key
2. Flushes Redis DB 0 (access keys) and DB 1 (response keys)
3. Restarts auth and all app services to regenerate and re-sign keys

**When to use:**
- Security incident response (suspected key compromise)
- Testing disaster recovery procedures
- Simulating emergency key rotation scenarios

**What happens:**
- All existing tokens become invalid immediately
- Services restart and generate new keys signed with the rotated HSM key
- Clients will need to re-authenticate
- Takes ~30 seconds for services to become ready

**What's preserved:**
- Redis DB 2 (access key hashes for refresh prevention)
- Redis DB 3 (revoked devices cache)
- Redis DB 4 (HSM keys - includes the newly rotated key)
- HSM identity (prefix) - remains the same
- User accounts and devices in Postgres - unchanged

**Side effects:**
- The current iOS client implementation caches response keys only when authenticated, so when this
happens they lose access and in the process that cache is cleared. This isn't perfect, but it's
better than not doing it. To be safer, remove the cache entirely at the expense of some more network
calls.

### Regenerating HSM Keys (Nuclear Reset)

The cleanest way to regenerate HSM keys and reset everything is the nuclear reset:

```bash
# Nuclear reset: delete everything, redeploy HSM/keys, export identity, deploy all
garden delete deploy && garden deploy hsm keys && ./scripts/export-hsm-identity.sh && garden deploy
```

This ensures:
- All deployments are removed cleanly
- PVCs are deleted automatically by Garden
- Fresh HSM keys are generated with a new identity (new key chain)
- New HSM identity is exported to `test-fixtures/hsm.id`
- All services are redeployed with the new identity

**Manual alternative** (if you only want to regenerate HSM without full reset):

```bash
# Delete existing identity
rm test-fixtures/hsm.id

# Redeploy HSM and keys
garden deploy hsm keys --force --log-level=verbose

# Export new identity
./scripts/export-hsm-identity.sh

# Redeploy services that depend on HSM identity
garden deploy auth app-ts app-rb app-rs app-py --force --log-level=verbose
```

### Restarting Services

```bash
# Delete and redeploy everything
garden delete deploy --log-level=verbose
garden deploy --log-level=verbose

# Restart stateless services (app-ts, app-rb, app-rs, app-py, auth, hsm, keys)
kubectl rollout restart deployment/app-ts -n better-auth-basic-example-dev

# Restart services with PVCs (postgres, redis) - DELETE POD INSTEAD
# Rolling restart causes issues with ReadWriteOnce PVCs
kubectl delete pod -n better-auth-basic-example-dev -l app=postgres
kubectl delete pod -n better-auth-basic-example-dev -l app=redis
```

**Important**: For Postgres and Redis (which use PersistentVolumeClaims), **delete the pod** rather than using `rollout restart`. The PVC can only be mounted by one pod at a time (ReadWriteOnce), so rolling restart will cause the new pod to wait for the old pod to release the volume.

**Simulating crashes**:
```bash
# Simulate postgres crash
kubectl delete pod -n better-auth-basic-example-dev -l app=postgres

# Simulate redis crash
kubectl delete pod -n better-auth-basic-example-dev -l app=redis

# Simulate stateless service crash (these handle rolling restart fine)
kubectl rollout restart deployment/app-ts -n better-auth-basic-example-dev
```

### Working with Multiple Implementations Simultaneously

```bash
# Deploy all app services
garden deploy app-ts app-rb app-rs app-py --log-level=verbose

# Watch logs from all app services
garden logs app-ts app-rb app-rs app-py --follow

# Test each implementation
curl http://app-ts.better-auth.local/health
curl http://app-rb.better-auth.local/health
curl http://app-rs.better-auth.local/health
curl http://app-py.better-auth.local/health
```

## iOS App Development

The iOS app (`clients/ios/BetterAuthBasicExample/`) demonstrates the full protocol:

### Running the iOS App

1. **Open in Xcode**:
   ```bash
   cd clients/ios
   open BetterAuthBasicExample.xcodeproj
   ```

2. **Ensure k8s deployment is running**:
   ```bash
   garden deploy --log-level=verbose
   ```

3. **Run on simulator** (Xcode → Product → Run)

4. **For device linking**, run two simulators:
   - Simulator 1: Create account, add device
   - Simulator 2: Link to account from Simulator 1

### Updating HSM Identity in iOS App

After regenerating HSM keys (via nuclear reset or manual regeneration):

1. **Get the new HSM identity**:
   ```bash
   # Should already exist from export-hsm-identity.sh
   cat test-fixtures/hsm.id
   ```

2. **Update iOS app**:
   ```swift
   // In clients/ios/BetterAuthBasicExample/Implementation/Stores/VerificationKeyStore.swift
   private let hsmIdentity = "EABcXYZ..."  // Update with value from hsm.id
   ```

3. **Rebuild app** in Xcode

**Note**: The HSM identity is the prefix from the HSM's key log and is used to verify the chain of trust for all keys.

### iOS App Architecture

```
BetterAuthBasicExample/
├── BetterAuthBasicExampleApp.swift  # App entry point
├── ContentView.swift                # Main UI
└── Implementation/
    ├── Crypto/                      # Secp256r1, Blake3, Argon2
    ├── Models/                      # AppState, response models
    ├── Network/                     # HTTP client
    ├── Protocol/                    # Protocol defaults (timeouts, etc.)
    ├── Stores/                      # Key stores with HSM verification
    ├── Time/                        # RFC3339 timestamper
    ├── Utilities/                   # Base64, Keychain, etc.
    └── Views/                       # SwiftUI views
```

## Monitoring Resource Usage

```bash
# Watch pod resource usage
kubectl top pods -n better-auth-basic-example-dev --watch

# Watch node resource usage
kubectl top nodes --watch

# View resource limits/requests
kubectl describe deployment app-ts -n better-auth-basic-example-dev | grep -A5 Limits
```

## Troubleshooting Development Issues

### Garden Says "No changes" But Code Changed

```bash
# Force rebuild
garden deploy <service> --force --log-level=verbose

# If that doesn't work, reset Garden's cache
garden util mutagen reset
```

### Docker Build Fails with Cryptic Error

```bash
# Build locally to see better error messages
cd services/<service>
docker build -t test-service .

# Check Docker daemon
docker ps
docker system df  # Check disk space
```

### Service Crashes Immediately After Deploy

```bash
# Check pod events
kubectl describe pod -n better-auth-basic-example-dev <pod-name>

# Check logs
kubectl logs -n better-auth-basic-example-dev <pod-name> --previous

# Common issues:
# - Missing environment variables
# - Can't connect to Redis/HSM
# - Port already in use
```

### Ingress Not Working

```bash
# Check ingress
kubectl get ingress -n better-auth-basic-example-dev

# Check /etc/hosts
cat /etc/hosts | grep better-auth

# Test service directly (bypass ingress)
kubectl port-forward -n better-auth-basic-example-dev svc/auth 8080:80
curl http://localhost:8080/health
```

### Redis Connection Errors

```bash
# Check Redis is running
kubectl get pods -n better-auth-basic-example-dev | grep redis

# Test Redis connection
kubectl exec -it -n better-auth-basic-example-dev deployment/redis -- redis-cli ping

# Check Redis from app pod
kubectl exec -it -n better-auth-basic-example-dev deployment/app-ts -- sh
# Inside container:
nc -zv redis 6379
```

**Redis Restart Recovery**:

Services handle Redis restarts with automatic reconnection:
- **Rust (app-rs)**: Uses retry logic with exponential backoff (3 attempts: 100ms, 200ms, 400ms)
- **TypeScript, Python, Ruby**: Connection libraries handle reconnection automatically

If you restart Redis (`kubectl delete pod -l app=redis`), services may show "broken pipe" or "connection refused" errors for 1-2 requests, then automatically recover. No service restart needed.

### HSM Service Not Responding

```bash
# Check HSM pod
kubectl get pods -n better-auth-basic-example-dev | grep hsm

# Check HSM logs (current pod)
kubectl logs -n better-auth-basic-example-dev deployment/hsm

# Check logs from previous crashed pod
kubectl logs -n better-auth-basic-example-dev deployment/hsm --previous

# Test HSM endpoint from auth pod
kubectl exec -it -n better-auth-basic-example-dev deployment/auth -- sh
# Inside container:
curl http://hsm:80/health
```

**HSM Segfault (SIGSEGV) During Rolling Restarts**:

If you see a segfault in HSM logs during rolling restarts with stack traces mentioning `pkcs11.(*Ctx).SignInit`, this indicates concurrent PKCS#11 operations. The HSM uses a mutex to serialize signing operations, but if you're modifying the HSM code, be aware:

- PKCS#11 sessions are **not thread-safe**
- Multiple concurrent `/sign` requests will cause segfaults without proper locking
- The `HSMServer.Sign()` method uses `sync.Mutex` to prevent this
- If you see this crash, ensure all PKCS#11 operations are protected by the mutex

To diagnose:
```bash
# Get logs from crashed pod
kubectl logs -n better-auth-basic-example-dev deployment/hsm --previous | grep -A20 "SIGSEGV"

# Look for this pattern in stack trace:
# github.com/miekg/pkcs11.(*Ctx).SignInit
# main.(*HSMServer).Sign
```

This typically happens when services restart simultaneously and make concurrent requests to HSM at startup.

### Integration Tests Failing

```bash
# Ensure all services are deployed
garden deploy --log-level=verbose

# Check service health
curl http://auth.better-auth.local/health
curl http://app-ts.better-auth.local/health

# Run tests with verbose output
cd ../../implementations/better-auth-ts
npm run test:k8s -- --verbose

# Common issues:
# - Stale keys in Redis (run FLUSHALL)
# - HSM key mismatch (regenerate and update tests)
# - Services still starting up (wait 30s after deploy)
```

## Tips and Tricks

### Quick Iteration on Service Code

```bash
# Terminal 1: Watch logs
garden logs app-ts --follow --log-level=verbose

# Terminal 2: Edit and deploy in a loop
vim services/app-ts/src/server.ts
garden deploy app-ts --log-level=verbose
# Repeat
```

### Debugging Garden Template Variables

Garden templates use `${...}` syntax. To see rendered manifests:

```bash
# Deploy with verbose logging to see rendered YAML
garden deploy app-ts --log-level=verbose

# Or get the deployed manifest from Kubernetes
kubectl get deployment app-ts -n better-auth-basic-example-dev -o yaml
```

### Faster Docker Builds

```dockerfile
# In Dockerfile, order commands by change frequency
# (rarely changed first, frequently changed last)

FROM node:20-slim
WORKDIR /app

# Dependencies (rarely change)
COPY package*.json ./
RUN npm ci --production

# Library (changes occasionally)
COPY services/dependencies/better-auth-ts /better-auth-ts

# Application code (changes frequently)
COPY services/app-ts/src ./src
COPY services/app-ts/tsconfig.json ./

RUN npm run build
CMD ["node", "dist/server.js"]
```

### Working Offline

Garden requires internet for some operations, but you can work offline if:
- All Docker images are already built and cached
- No external dependencies need downloading

```bash
# Build everything while online
garden build --log-level=verbose

# Then work offline
garden deploy --log-level=verbose  # Uses cached builds
```

## Additional Resources

- [Garden.io Documentation](https://docs.garden.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Better Auth Protocol Specification](../../README.md)
- [Better Auth Development Guide](../../CLAUDE.md)
