# Better Auth - Basic Kubernetes Example with Garden.io

This example demonstrates a production-like Better Auth deployment using Garden.io for local Kubernetes development.

## Architecture

This example consists of two services:

1. **Auth Server (Go)**: Provides authentication services using the `better-auth-go` library
   - Handles account creation, recovery, deletion
   - Device linking/unlinking and rotation
   - Session management (request, create, refresh)
   - Issues and validates access tokens

2. **Application Server (TypeScript)**: Example application that uses auth tokens
   - Demonstrates how to integrate with Better Auth
   - Provides a protected endpoint
   - Uses the `better-auth-ts` access verifier

3. **Keys Server (Ruby)**: Example key service that provides a set of valid response keys from redis
   - Exposes response public keys for client side verification

4. **Redis**: Backing store for current public keys
   - Access keys are in DB 0
   - Response keys are in DB 1

## Prerequisites

### Required

1. **Docker Desktop with Kubernetes enabled**
   - Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   - Enable Kubernetes: Settings → Kubernetes → Enable Kubernetes

2. **Garden CLI**
   ```bash
   # macOS
   brew install garden-io/garden/garden-cli

   # Linux
   curl -sL https://get.garden.io/install.sh | bash

   # Windows (via Chocolatey)
   choco install garden-cli
   ```

3. **Go 1.22+** and **Node.js 20+** (for local development)

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

### 2. Deploy Everything

Garden will build Docker images, deploy to Kubernetes, and set up port forwarding:

```bash
garden deploy
```

This command will:
- Build the auth Docker image
- Build the app Docker image
- Create Kubernetes deployments and services
- Forward ports for local access:
  - Auth Server: http://localhost:8080
  - App Server: http://localhost:3000

### 3. Verify Deployment

Check that both services are healthy:

```bash
# Check pod status
kubectl get pods -n better-auth-basic-example-dev

# View logs
garden logs auth
garden logs app
garden logs keys
```

### 4. Update /etc/hosts

Add these lines

```
127.0.0.1 auth.better-auth.local
127.0.0.1 app.better-auth.local
127.0.0.1 keys.better-auth.local
```

### 5. Test the Services

From the typescript implementation:

```bash
npm run test:k8s
```

## Garden Commands

### Development Workflow

```bash
# Deploy all services
garden deploy

# Deploy specific service
garden deploy auth
garden deploy app
garden deploy keys

# View logs
garden logs auth
garden logs app
garden logs keys
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
kubectl exec -it -n better-auth-basic-example-dev deployment/app -- sh

# Port forward manually if needed
kubectl port-forward -n better-auth-basic-example-dev deployment/auth 8080:8080
kubectl port-forward -n better-auth-basic-example-dev deployment/app 3000:3000

# View Garden dashboard
garden dashboard
```

## Project Structure

```
examples/basic/
├── project.garden.yml              # Main Garden project configuration
├── README.md                       # This file
└── services/
    ├── auth/                # Go authentication server
    │   ├── Dockerfile              # Multi-stage build (Debian-based)
    │   ├── garden.yml              # Service-specific Garden config
    │   ├── manifests.yml           # Kubernetes manifests
    │   ├── go.mod                  # With replace directive for local lib
    │   └── main.go                 # Server implementation
    └── app/                 # TypeScript application server
        ├── Dockerfile              # Multi-stage build (Debian-based)
        ├── garden.yml              # Service-specific Garden config
        ├── manifests.yml           # Kubernetes manifests
        ├── package.json            # With file: reference for local lib
        ├── tsconfig.json           # TypeScript configuration
        └── src/
            └── server.ts           # Application server implementation
```

## How It Works

### Garden Configuration

**Project Level** (`project.garden.yml`):
- Defines the project name and environments
- Configures the `local-kubernetes` provider
- Sets default namespace and resource limits
- Defines shared variables

**Service Level** (`garden.yml` in each service):
- Defines Build actions (Docker image builds)
- Defines Deploy actions (Kubernetes deployments)
- Defines Test actions (health checks)
- Specifies dependencies between services
- Configures port forwarding

### Kubernetes Manifests

Each service has a `manifests.yml` file that defines:
- **Deployment**: Pod specification with container image, environment variables, health checks
- **Service**: ClusterIP service for internal communication

Garden injects the built Docker image reference using template variables:
```yaml
image: ${actions.build.auth.outputs.deployment-image-id}
```

### Service Communication

Services synchronize keys in redis. That is all.

## Customization

### Change Port Numbers

Edit `project.garden.yml`:
```yaml
variables:
  authServerPort: "8080"  # Change here
  appServerPort: "3000"   # Change here
```

Then update the corresponding manifests and code.

### Add More Services

1. Create a new directory under `services/`
2. Add Dockerfile, garden.yml, and manifests.yml
3. Reference Better Auth library using the appropriate method for your language
4. Deploy with `garden deploy <service-name>`

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

### Port conflicts

If ports 8080 or 3000 are already in use, change them in `project.garden.yml` and redeploy.

### Garden CLI issues

```bash
# Clear Garden cache
garden util clean

# Update Garden CLI
brew upgrade garden-cli  # macOS
```

## Next Steps

- Add database persistence (PostgreSQL)
- Add more complex authentication flows
- Add monitoring and observability (Prometheus, Grafana)
- Create additional language implementations (Python, Rust)

## Resources

- [Garden.io Documentation](https://docs.garden.io)
- [Better Auth Specification](../../README.md)
- [better-auth-go](../../implementations/better-auth-go/)
- [better-auth-ts](../../implementations/better-auth-ts/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
