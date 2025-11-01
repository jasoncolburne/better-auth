# Better Auth - Basic Kubernetes Example with Garden.io

This example demonstrates a production-like Better Auth deployment using Garden.io for local Kubernetes development.

## Security

### Root (HSM)

The security of this system rests on forward secrecy and hardware-backed keys. By pre-generating
securely stored keys and committing to them using forward secrecy, we build recovery avenues for
identifiers associated with such keys.

To ensure that the identifiers are tightly bound to the keys they are associated with, several
measures are taken:
- In addition to commitments to keys revealed in the future, each event about an identifier's keys
is chained back to the previous event.
- By creating content-addressable, embedded identifiers in each event, we can prove that the event
has not been tampered.
- When creating the self-addressing identifier, we'll also do something special for the first record
in the chain. We replicate the process across another field, and both the id and this field (we'll
call it the prefix since it prefixes the sequence). It remains constant for the entire chain, and
identifies the chain.
- The prefix is also the id of the first event.
- By signing each event with the key revealed in that event, we create a self-certifying keychain.
- If we add timestamps, we know which generation of key created a given signature.
- If we add another field called `taintPrevious` we can invalidate keys for cases where previous
signatures remain valid for a duration of time (think tokens).
- We can add sequence numbers to create an easy way to prevent divergence of the chain. If two
events share the same sequence number, the entire key chain is contested, and a rotation is required
to regain control. This next event's previous field will indicate the correct previous event.

This is what such a key chain looks like:

```
...   Event N-1    ...    Event N     ...     Event N+1     ...

      Prefix       =      Prefix       =      Prefix
      SequenceNumber=N-1  SequenceNumber=N    SequenceNumber=N+1
      CreatedAt=...       CreatedAt=...       CreatedAt=...
                                              TaintPrevious=True
      Previous
      Id<-----------------Previous
                          Id<-----------------Previous
                                              Id
      PublicKey
      RotationHash------->PublicKey
                          RotationHash------->PublicKey
                                              RotationHash
```

- Id - The self-addressing identifier for the event.
- Prefix - The self-addressing identifier for event 0 in this chain.
- Previous (Optional) - The previous event's Id
- PublicKey - The current generation's signing key's verification key
- RotationHash - A commitment to the next public key
- SequenceNumber - Increments by 1, starts at 0, no two events can share the same sequence number.
- CreatedAt - A timestamp, always increases.
- TaintPrevious (Optional) - True if the rotation was due to a compromised key.

In the example, generation N is tainted and signatures created with it, no matter how recent, should
not be respected. This permits zero-downtime hsm key rotation with an optional lookback window,
without the need to log and distribute each signature on its respective key chain.

Each event is signed with the signing key that corresponds to the event's PublicKey.

Now that we've created a self-certifying key chain, we can apply it to the HSM described below and
burn the chain's prefix into all the software to prevent impersonation, without the need for complex
recovery mechanisms.

#### Differences between this and a KERI KEL

Typically in a KEL, a record of each signature is burned into the key chain. In this model, we use
timestamps and the concept of tainting to acheive a similar result.

### Verifiers

All verifiers follow this pattern:

1. Verify HSM key chain, removing stale/tainted keys
2. Verify key authorization signature with valid HSM key
3. Verify payload signature with key

#### Services

Each server generates a response signing key and has it endorsed by the HSM upon startup, and the
servers are cycled every 12 hours. Additionally, the auth servers generate access signing keys and
these are also endorsed by the HSM.

When any server needs to verify an access key signature created by an auth server, it checks the hsm
key chain and authorization to ensure the key is valid.

When the HSM key is tainted, it is critical to restart all the services. This informs clients, by
virtue of the new hsm key they will see, that there has been an update to the key chain - which is
how they detect the taint.

#### Clients

Client key chains are similar to the HSM key chain, but are instead managed by the auth service
through a storage abstraction (in a postgres db in this example). Management requests are signed
by the client keys, and forward secrecy/hardware are employed to protect the identifier of the
client.

When clients receive responses the keys used to create response signatures are verified to be
correctly endorsed by the hsm.

### Known Weaknesses

- Brute force of the current HSM key and masquerading as the backend (recoverable by
  rotation/tainting)
- Physical theft of an unlocked client device (recoverable by recovery/unlinking)
- Code execution on an app or auth service (recoverable by rotating/tainting/rolling)

## Architecture

This example consists of multiple services:

1. **Auth Service (Go)**: Provides authentication services using the `better-auth-go` library
   - Handles account creation, recovery, deletion
   - Device linking/unlinking and rotation
   - Session management (request, create, refresh)
   - Issues and validates access tokens

2. **Application Services** (4 language implementations): Example applications that use auth tokens
   - **app-ts (TypeScript)**: Uses the `better-auth-ts` access verifier
   - **app-rb (Ruby)**: Uses the `better-auth-rb` access verifier
   - **app-rs (Rust)**: Uses the `better-auth-rs` access verifier
   - **app-py (Python)**: Uses the `better-auth-py` access verifier
   - Each demonstrates how to integrate with Better Auth
   - Each provides the same protected `/foo/bar` endpoint
   - Each returns a unique `serverName` field to identify which implementation handled the request

3. **Keys Service (Ruby)**: Serves HSM-signed keys to clients
   - Fetches HSM-signed keys from Redis
   - Returns signed keys directly (clients verify HSM signatures)
   - Provides `/keys` endpoint for all keys or `/keys/:identity` for specific keys
   - Provides `/hsm/keys` for hsm key chain

4. **HSM Service (Go)**: Hardware Security Module simulator for centralized key signing
   - Signs all public keys (access and response) when services start
   - Provides `/sign` endpoint that signs arbitrary payloads with a rotating HSM key
   - Provides `/rotate` endpoint that rotates to a new HSM key
   - Provides `/taint` endpoint that taints the current HSM key and rotates to a new one
   - In production, this would be backed by a real HSM with secure key storage
   - HSM identity is hardcoded in clients

5. **Redis**: Backing store for HSM-signed keys and session key hashes
   - Uses persistent storage (64Mi PersistentVolumeClaim with AOF)
   - Data survives pod restarts and redeployments
   - DB 0: HSM-signed access keys (from auth service, verified by app services)
   - DB 1: HSM-signed response keys (from auth and app services, verified by clients)
   - DB 2: AccessKey hashes, for rejecting refreshes of public access keys that have already been
     refreshed
   - DB 3: Revoked devices. For rejecting access to devices within the access lifetime window, or
     without a TTL, this could be used to ban users and prevent resource access
   - DB 4: HSM keys, chained and self-certifying

6. **PostgreSQL**: Database for auth and hsm services
   - Uses persistent storage (256Mi PersistentVolumeClaim)
   - Stores accounts, devices, and authentication state
   - Data survives pod restarts and redeployments

## Prerequisites

### Required

1. **Docker Desktop with Kubernetes enabled (or equivalent)**
   - Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   - Enable Kubernetes: Settings → Kubernetes → Enable Kubernetes
   - Podman+k8s, minikube, k3s etc should all be supported but haven't been tested

2. **Garden CLI**
   ```bash
   # macOS
   brew install garden-io/garden/garden-cli

   # Linux
   curl -sL https://get.garden.io/install.sh | bash

   # Windows (via Chocolatey)
   choco install garden-cli
   ```

3. **iOS toolchain (there are plans to make an Android app)**
   Use XCode.

### Verify Setup

```bash
# Check Docker Desktop Kubernetes is running
kubectl cluster-info

# Check Garden CLI is installed
garden version

# Verify you're in the correct context
kubectl config current-context
# Should show: docker-desktop (or similar)
```

## Local Library Referencing

This example demonstrates how to reference Better Auth libraries locally without publishing them. Each language has its own approach:

### Go (`better-auth-go`)

Uses Go's `replace` directive in `go.mod`:

```go
module github.com/jasoncolburne/better-auth/examples/basic/auth

require github.com/jasoncolburne/better-auth-go v0.1.0

// Use local implementation
replace github.com/jasoncolburne/better-auth-go => ../../../implementations/better-auth-go
```

The Dockerfile copies the local implementation:
```dockerfile
COPY ../../../implementations/better-auth-go /better-auth-go
```

### TypeScript (`better-auth-ts`)

Uses npm's `file:` protocol in `package.json`:

```json
{
  "dependencies": {
    "better-auth-ts": "file:../../../implementations/better-auth-ts"
  }
}
```

The Dockerfile builds the library first, then installs it:
```dockerfile
COPY ../../../implementations/better-auth-ts /better-auth-ts
WORKDIR /better-auth-ts
RUN npm install && npm run build
```

### Python (`better-auth-py`)

Would use pip's editable install in Dockerfile:
```dockerfile
COPY ../../../implementations/better-auth-py /better-auth-py
RUN pip install -e /better-auth-py
```

Or in `requirements.txt`:
```
-e file:///better-auth-py
```

### Rust (`better-auth-rs`)

Would use path dependencies in `Cargo.toml`:
```toml
[dependencies]
better-auth = { path = "../../../implementations/better-auth-rs" }
```

The Dockerfile would copy the implementation similar to Go:
```dockerfile
COPY ../../../implementations/better-auth-rs /better-auth-rs
```

## Getting Started

### 1. Navigate to Example Directory

```bash
cd examples/basic
```

### 2. Deploy HSM and Keys services (required for identity export)

```bash
garden deploy hsm keys
```

### 3. Export HSM identity

```bash
scripts/export-hsm-identity.sh
```

### 4. Deploy everything

Garden will build Docker images, deploy to Kubernetes, and set up ingresses:

```bash
garden deploy
```

This command will:
- Build the auth Docker image
- Build the app Docker images (TypeScript, Ruby, Rust, Python)
- Build the keys Docker image
- Create Kubernetes deployments and services
- Setup ingresses for local access:
  - Auth Service: http://auth.better-auth.local/
  - App Services:
    - TypeScript: http://app-ts.better-auth.local/
    - Ruby: http://app-rb.better-auth.local/
    - Rust: http://app-rs.better-auth.local/
    - Python: http://app-py.better-auth.local/
  - Keys Service: http://keys.better-auth.local/

### 5. Verify Deployment

Check that all services are healthy:

```bash
# Check pod status
kubectl get pods -n better-auth-basic-example-dev

# View logs
garden logs auth
garden logs app-ts
garden logs app-rb
garden logs app-rs
garden logs app-py
garden logs keys
```

### 6. Update /etc/hosts

Add these lines

```
127.0.0.1 auth.better-auth.local
127.0.0.1 app-ts.better-auth.local
127.0.0.1 app-rb.better-auth.local
127.0.0.1 app-rs.better-auth.local
127.0.0.1 app-py.better-auth.local
127.0.0.1 keys.better-auth.local
```

### 7. Test the Services

Check for keys:

```bash
curl http://keys.better-auth.local/keys
```

Check that this fails (it's not going to be able to find the key in redis, and the token is
expired) - you can try any of the app servers:

```bash
# Try TypeScript implementation
curl -X POST -d '{"payload":{"access":{"nonce":"0ACiyd8ipcuCR2OPObSZpxpG","timestamp":"2025-10-12T23:46:50.312000000Z","token":"0ICzKIW-OBWIYEb-V_m4KzLDiexBaAK5WffDEwesi-G_-40g4XllepYgJaygNI1munYOoC7lPEkZmtzjFXqpCEXjH4sIAAAAAAAC_2yOWW-bQBRG_8t9NhUzZnDCG068QOo6LAnBVYXAXMw4ZvHMQAKR_3vlSl2k5vXq3O-cD5AoehROjrXiagALiG079qEiiT9EN3HkVSGe07twI9zktdzMDOMl0QOvKlaMxXXRGjCBHHu-R7BgsdUe2vOR7UatiHzXd0jiOUX8hMYzebuN3XiUgcmJnZryABPgf60LlyWPeUXF2BaHzLD7WZitgvLeS-zDzZmutszZ1dp8FuOyhwm0XXbi-wf8E1xVR2PY50ZeR9O5PrqROkbjkjf7jbhfBLt27Q1D8hgv754oTEA0KlW8qdepLH_J0fe-NcXXnJVa7tOX7aCC9XtbO-wUZ8--3cnmxJavvT_k12wpO8xtBRZQnTKN6BqhIZ1ahmkx_cuUEDKjhkl3MAF8b7kY_iWnoa5bOvmPFFgIlOXikwdCfk_rt-aUmLMrnyoleNYplGB9QIui4lLyppbzwW9OeD12EgVY30Fgeu1-E1wh_LhcLj8DAAD__wM5bjb3AQAA"},"request":{"foo":"bar","bar":"foo"}},"signature":"0IDxi-eJgnOrdV86w6pTk7_cLFT2NOuDDrVabWk6bDHcNHB9VJb3qVNhK-vIJ4pPSnmApdmZ2iiCiuGuod-rzIWP"}' http://app-ts.better-auth.local/foo/bar

# Or try Ruby implementation
curl -X POST -d '...' http://app-rb.better-auth.local/foo/bar

# Or try Rust implementation
curl -X POST -d '...' http://app-rs.better-auth.local/foo/bar

# Or try Python implementation
curl -X POST -d '...' http://app-py.better-auth.local/foo/bar
```

If you dump backend logs for the app servers you'll see the error.

Next, from the typescript implementation:

```bash
npm run test:k8s
```

### 8. Build the iOS app

There is an iOS app that can be built using `make simulator`. You can run two and exercise the
entire set of protocols.

## Garden Commands

### Development Workflow

```bash
# Deploy all services
garden deploy

# Deploy specific service
garden deploy auth
garden deploy app-ts
garden deploy app-rb
garden deploy app-rs
garden deploy app-py
garden deploy keys
garden deploy hsm

# View logs
garden logs auth
garden logs app-ts
garden logs app-rb
garden logs app-rs
garden logs app-py
garden logs keys
garden logs hsm
garden logs --follow  # Follow all logs

# Get service status
garden get status

# Delete all deployments
garden delete deploy
```


### Debugging

```bash
# Shell into running container
kubectl exec -it -n better-auth-basic-example-dev deployment/auth -- sh
kubectl exec -it -n better-auth-basic-example-dev deployment/app-ts -- sh
kubectl exec -it -n better-auth-basic-example-dev deployment/app-rb -- sh
kubectl exec -it -n better-auth-basic-example-dev deployment/app-rs -- sh
kubectl exec -it -n better-auth-basic-example-dev deployment/app-py -- sh
kubectl exec -it -n better-auth-basic-example-dev deployment/keys -- sh
kubectl exec -it -n better-auth-basic-example-dev deployment/hsm -- sh
```

### HSM Identity Setup

After deploying HSM and keys services, export the HSM identity for use by auth and app services:

```bash
# Deploy HSM and keys services first
garden deploy hsm keys

# Export HSM identity to test-fixtures/hsm.id
./scripts/export-hsm-identity.sh
```

The HSM identity is required by auth and app services to verify the chain of trust for keys published by the keys service. The exported identity is stored in `test-fixtures/hsm.id` (gitignored) and is injected into service code at build time.

**When to re-export:**
- After initial HSM deployment
- Before building/deploying auth/app services or clients if `test-fixtures/hsm.id` doesn't exist
- After regenerating HSM keys (see nuclear reset below)

**Note:** The HSM identity (prefix) does not change during key rotation, so you only need to export it once per deployment environment unless you regenerate the HSM keys.

### HSM Key Rotation

To manually rotate the HSM signing key:

```bash
./scripts/rotate-hsm-key.sh
```

This rotates the HSM signing key and displays the new public key. Services automatically pick up the new key on their next HSM interaction. The HSM identity (prefix) remains unchanged.

**When to use:**
- Testing key rotation logic
- Manual key rotation as part of planned security procedures

### Service Key Purge and Rollout

If a service key (not HSM key) is suspected to be compromised:

```bash
./scripts/purge-keys-and-roll-services.sh
```

This purges service keys and restarts services:
1. Flushes Redis access keys (DB 0) and response keys (DB 1)
2. Restarts auth and all app services

**Result:**
- All existing tokens become invalid immediately
- Services regenerate keys using the existing (uncompromised) HSM key.
- Clients must re-authenticate
- Takes ~30 seconds for services to become ready

**When to use:**
- Service key compromise (auth or app service key leaked)
- HSM key is known to be secure

### Emergency Key Rotation (Red Button)

For emergency situations requiring immediate key rotation:

```bash
./scripts/red-button.sh
```

This performs a complete emergency rotation:
1. Rotates the HSM signing key
2. Flushes Redis access keys (DB 0) and response keys (DB 1)
3. Restarts auth and all app services

**Result:**
- All existing tokens become invalid immediately
- Services generate new keys signed with the rotated HSM key
- Clients must re-authenticate
- Takes ~30 seconds for services to become ready

**When to use:**
- Security incident response (suspected hsm key compromise)
- Testing disaster recovery procedures

## Project Structure

```
examples/basic/
├── project.garden.yml              # Main Garden project configuration
├── README.md                       # This file
└── services/
    ├── auth/                       # Go authentication server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests
    │   ├── go.mod                  # With replace directive for local lib
    │   └── main.go                 # Server implementation
    ├── app-ts/                     # TypeScript application server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests
    │   ├── package.json            # With file: reference for local lib
    │   ├── tsconfig.json           # TypeScript configuration
    │   └── src/
    │       └── server.ts           # Application server implementation
    ├── app-rb/                     # Ruby application server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests
    │   ├── Gemfile                 # With path reference for local lib
    │   ├── config.ru               # Rack config
    │   ├── server.rb               # Application server implementation
    │   └── lib/                    # Crypto, storage, encoding utilities
    ├── app-rs/                     # Rust application server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests
    │   ├── Cargo.toml              # With path reference for local lib
    │   └── src/
    │       ├── main.rs             # Application server implementation
    │       └── implementation/     # Crypto, storage, encoding utilities
    ├── app-py/                     # Python application server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests
    │   ├── requirements.txt        # With file reference for local lib
    │   └── server.py               # Application server implementation
    ├── keys/                       # Ruby keys server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests
    │   ├── Gemfile                 # Dependencies
    │   ├── config.ru               # Rack config
    │   └── server.rb               # Keys server implementation
    ├── hsm/                        # Go HSM simulator
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml.tpl       # Kubernetes manifests (no Ingress)
    │   ├── go.mod                  # With replace directive for local lib
    │   └── main.go                 # HSM service implementation
    ├── redis/                      # Redis deployment
    │   ├── garden.yml              # Service-specific Garden config
    │   └── manifests.yml           # Kubernetes manifests
    ├── restart-controller/         # Service account for rolling restarts
    │   ├── garden.yml              # Service-specific Garden config
    │   └── manifests.yml.tpl       # Kubernetes manifests
    ├── dependencies/               # Symlinks to implementations
    │   ├── better-auth-ts -> ../../../../implementations/better-auth-ts
    │   ├── better-auth-rb -> ../../../../implementations/better-auth-rb
    │   ├── better-auth-rs -> ../../../../implementations/better-auth-rs
    │   └── better-auth-py -> ../../../../implementations/better-auth-py
    └── clients/
        └── ios/                    # iOS client app
            └── BetterAuthBasicExample/
                ├── BetterAuthBasicExampleApp.swift
                ├── ContentView.swift
                └── Implementation/
                    ├── Crypto/     # Secp256r1, Blake3, Argon2 implementations
                    ├── Models/     # AppState and response models
                    ├── Network/    # HTTP client
                    ├── Protocol/   # Better Auth protocol defaults
                    ├── Stores/     # Key stores (includes HSM verification)
                    ├── Time/       # RFC3339 timestamper
                    ├── Utilities/  # Base64, Keychain, etc.
                    └── Views/      # SwiftUI views for auth flow
```

## How It Works

### Garden Configuration

**Project Level** (`project.garden.yml`):
- Defines the project name and environments
- Configures the `local-kubernetes` provider
- Defines shared variables

**Service Level** (`garden.yml` in each service):
- Defines Build actions (Docker image builds)
- Defines Deploy actions (Kubernetes deployments)
- Specifies dependencies between services

### Kubernetes Manifests

Each service has a `manifests.yml.tpl` file that defines:
- **Deployment**: Pod specification with container image, environment variables, health checks
- **Service**: ClusterIP service for internal communication
- **Ingress**: Ingress into the service from the nginx proxy

Garden injects the built Docker image reference using template variables:
```yaml
image: ${actions.build.auth.outputs.deployment-image-id}
```

### Rolling Restart CronJobs

Each service (auth, app-ts, app-rb, app-rs, app-py) includes a CronJob that performs rolling restarts every 12 hours. This ensures:
- Fresh keys are rotated regularly (keys expire after 12 hours by default)
- Memory leaks or resource drift don't accumulate over time
- Services pick up any configuration changes from ConfigMaps/Secrets

**CronJob Configuration**:
```yaml
spec:
  schedule: "0 */12 * * *"           # Every 12 hours (midnight and noon UTC)
  successfulJobsHistoryLimit: 0     # Clean up successful jobs immediately
  failedJobsHistoryLimit: 2         # Keep last 2 failed jobs for debugging
  concurrencyPolicy: Forbid          # Prevent overlapping restarts
```

The history limits ensure that `kubectl get jobs` output remains clean - you'll only see failed jobs (if any) rather than having successful job completions pile up. This configuration prioritizes operational clarity while retaining failed job history for troubleshooting.

**Why Rolling Restarts?**:
- Services generate cryptographic keys with 12-hour expiration
- Rolling restarts ensure services regenerate keys before expiration
- Zero-downtime: Kubernetes performs gradual pod replacement
- The restart controller uses a ServiceAccount with RBAC permissions to execute `kubectl rollout restart`

### Service Communication

Services synchronize keys in redis, they don't communicate for auth. This is by design.

### HSM Key Signing Flow

The HSM service provides centralized key signing to prevent unauthorized keys from being used:

1. **Key Registration** (on service startup):
   - Auth service generates access and response key pairs
   - App services generate response key pairs
   - Each service creates a payload: `{purpose, publicKey, expiration}`
   - Services POST payload to HSM `/sign` endpoint
   - HSM signs the payload and returns `{body: {payload, hsmIdentity}, signature}`
   - Services store the complete HSM response in Redis

2. **Key Verification** (on every access request):
   - App services fetch keys from Redis DB 0 (access keys)
   - Clients fetch keys from keys service which reads Redis DB 1 (response keys)
   - Verifiers fetch the HSM key chain from the keys service which reads from Redis DB 3 (hsm keys)
   - Verifiers verify the key chain and cache any live keys for use
   - Verifiers extract the body JSON and signature from HSM response
   - Verifiers attempt to verify the signature using a live, cached key
   - Verifiers check: HSM identity matches, purpose is correct, key not expired, self-certification
     is valid
   - Only after verification passes is the public key extracted and used

This ensures that even if Redis is compromised, attackers cannot inject unauthorized keys without the HSM private key.

## Customization

### Add More Services

1. Create a new directory under `services/`
2. Add Dockerfile, garden.yml, and manifests.yml.tpl
3. Connect your access key store to redis
4. Register your response key in redis
5. Verify requests using the Access Verifier from the Better Auth library in your language
6. Deploy with `garden deploy <service-name>`

### Use Remote Kubernetes Cluster

Edit `project.garden.yml` to add a new environment:
```yaml
environments:
  - name: local
    defaultNamespace: better-auth-dev
  - name: staging
    defaultNamespace: better-auth-staging

providers:
  - name: local-kubernetes
    environments: [local]
  - name: kubernetes
    environments: [staging]
    context: my-staging-cluster  # Your kubeconfig context
```

Then deploy to staging:
```bash
garden deploy --env staging
```

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n better-auth-dev

# Describe pod to see events
kubectl describe pod -n better-auth-dev <pod-name>

# Check logs
kubectl logs -n better-auth-dev <pod-name>
```

### Build failures

```bash
# Clean and rebuild
garden delete deploy
garden build --force
garden deploy
```

### Garden CLI issues

```bash
# Clear Garden cache
garden util clean

# Update Garden CLI
brew upgrade garden-cli  # macOS
```

### Nuclear Reset (Complete Fresh Start)

If you need to completely reset the environment including HSM identity, PVCs, and all state:

```bash
# Delete everything, redeploy HSM and keys, export new identity, then deploy all services
garden delete deploy && garden deploy hsm keys && ./scripts/export-hsm-identity.sh && garden deploy
```

This will:
1. Delete all deployments and clean up resources
2. Automatically delete both Redis and Postgres PVCs (Garden handles this)
3. Deploy HSM and keys services with fresh keys
4. Export the new HSM identity to `test-fixtures/hsm.id`
5. Deploy all remaining services with the new HSM identity

**When to use nuclear reset:**
- Starting completely fresh with new HSM keys
- PVCs are corrupted or in a bad state
- Need to test a clean deployment from scratch
- Troubleshooting complex state issues across multiple services (this example shouldn't be an issue)

### Persistent data survives deployments

Redis, postgres and the HSM all use persistent storage. If you want to start fresh you can delete
them.

```bash
# Delete deployment and all PVCs
kubectl delete deployment redis postgres hsm
kubectl delete pvc redis-data postgres-data softhsm-tokens -n better-auth-basic-example-dev

# Redeploy (creates new PVCs)
garden deploy hsm keys && scripts/export-hsm-identity.sh && garden deploy
```

### Resetting specific databases

```bash
# Reset Redis only (flush all data)
kubectl exec -it -n better-auth-basic-example-dev deployment/redis -- redis-cli FLUSHALL

# Reset Postgres only (drop and recreate database)
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -c "DROP DATABASE better_auth;"
kubectl exec -it -n better-auth-basic-example-dev deployment/postgres -- psql -U postgres -c "CREATE DATABASE better_auth;"
kubectl rollout restart deployment/auth -n better-auth-basic-example-dev
```

### PVC stuck in pending state

```bash
# Check PVC status
kubectl get pvc -n better-auth-basic-example-dev

# Describe PVC to see events
kubectl describe pvc redis-data -n better-auth-basic-example-dev
kubectl describe pvc postgres-data -n better-auth-basic-example-dev

# Common causes:
# - No storage class available (Docker Desktop should provide one automatically)
# - Insufficient disk space
# - PVC already exists and is bound to different pod
```

## Next Steps

- Add more complex authentication flows
- Add monitoring and observability (Prometheus, Grafana)
- Add client implementations for Swift, Dart, and Kotlin

## Resources

- [Garden.io Documentation](https://docs.garden.io)
- [Better Auth Specification](../../README.md)
- [better-auth-go](../../implementations/better-auth-go/)
- [better-auth-ts](../../implementations/better-auth-ts/)
- [better-auth-rb](../../implementations/better-auth-rb/)
- [better-auth-rs](../../implementations/better-auth-rs/)
- [better-auth-py](../../implementations/better-auth-py/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
