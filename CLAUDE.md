# Better Auth - Protocol Specification

## Project Overview

Better Auth is a **multi-repository, multi-language authentication protocol** spanning 9 repositories:
- 1 specification repository (this one)
- 8 implementation repositories across different languages

This is the **specification repository** that defines the core protocol. All implementations follow this spec.

## Multi-Repository Architecture

All implementation repositories are included as **git submodules** in the `implementations/` directory. Each submodule is configured with:
- SSH URLs for authentication (`git@github.com:jasoncolburne/better-auth-*.git`)
- Branch tracking pointing to `main`
- Standardized Makefiles for common operations

Submodules track specific commits to ensure reproducible builds, while branch tracking makes it easy to pull latest changes from `main`.

### Implementation Repositories

**Full Implementations (Client + Server):**
- [better-auth-ts](https://github.com/jasoncolburne/better-auth-ts) - TypeScript (Reference Implementation)
- [better-auth-py](https://github.com/jasoncolburne/better-auth-py) - Python
- [better-auth-rs](https://github.com/jasoncolburne/better-auth-rs) - Rust

**Server-Only Implementations:**
- [better-auth-go](https://github.com/jasoncolburne/better-auth-go) - Go
- [better-auth-rb](https://github.com/jasoncolburne/better-auth-rb) - Ruby

**Client-Only Implementations:**
- [better-auth-swift](https://github.com/jasoncolburne/better-auth-swift) - Swift
- [better-auth-dart](https://github.com/jasoncolburne/better-auth-dart) - Dart
- [better-auth-kt](https://github.com/jasoncolburne/better-auth-kt) - Kotlin

### Reference Implementation

**better-auth-ts** is the reference implementation and is used to generate the examples in this README using CESR (Composable Event Streaming Representation) encoding.

## Core Design Principles

1. **All actions except authentication to acquire an access session are gated by a rotation operation**
2. **All requests contain a nonce to challenge the server**
3. **Authentication is a two phase operation that involves the server challenging the client**
4. **Rotations are protected using forward commitment**

## Protocol Philosophy

Better Auth is designed to be:
- **Platform agnostic**: Works across any platform
- **Encoding agnostic**: Not tied to a specific encoding format (though examples use CESR)
- **Crypto agnostic**: Bring your own cryptographic primitives
- **Storage agnostic**: Implement your own storage layer

## Protocol Structure

### Data Contexts

All protocol request/response payloads contain these contexts:
- `access`: Information relevant to the request/response pair
- `request`/`response`: The request or response data

These contexts are further broken down into:
- `access`: Information that permits access by the current device
- `authentication`: Information that permits authentication of the current device
- `link`: Information about another device (used in device linking)

### Protocol Groups

There are 3 main protocol groups plus 1 access protocol:

1. **Account Protocols**: CreateAccount, DeleteAccount, RecoverAccount
2. **Device Protocols**: LinkDevice, UnlinkDevice, RotateDevice
3. **Session Protocols**: RequestSession, CreateSession, RefreshSession
4. **Access Protocol**: Generic access requests with arbitrary payloads

## Key Protocol Concepts

### Forward Commitment via Key Rotation

Keys are rotated by:
1. Pre-committing to the next key using a hash (rotationHash)
2. When rotating, revealing the key that matches the previous hash
3. Establishing a new rotationHash for the next rotation

This creates a hash chain that provides forward commitment - compromising the current key doesn't reveal other keys
and rotation permits recovery of the chain.

### Device Identity

A `device` identifier is a hash digest of:
- `publicKey`: The current authentication public key
- `rotationHash`: The hash of the next authentication key

This binding ensures device identity is tied to the key rotation chain.

### Two-Phase Authentication

Authentication requires two round trips:
1. **RequestSession**: Client sends identity, server responds with challenge nonce
2. **CreateSession**: Client signs challenge with device key, server issues access token

This prevents replay attacks and ensures liveness.

### Access Tokens

Access tokens contain:
- Device and identity information
- Current access public key and rotation hash
- Issued/expiry timestamps
- Custom attributes (e.g., permissions)

Tokens are signed by the server and can be verified independently, permitting efficient scaling.

## Message Flow Patterns

### Account Creation
Client generates keypairs → Client sends authentication details → Server verifies and stores

### Authentication
Client requests challenge → Server sends nonce → Client signs nonce → Server issues token

### Access Request
Client signs request with access key → Server verifies token and signature → Server processes request

### Key Rotation (Authentication or Access)
Client reveals previous rotation key → Client establishes new rotation hash → Server verifies chain

### Device Linking
New device generates keys → Existing device endorses new device → Server validates both signatures

### Account Recovery
Client signs with recovery key → Server validates against recovery hash → Client establishes new device

## Implementation Guidelines

### What Implementations Must Provide

All implementations must provide interfaces for:
- **Hashing**: Cryptographic hash function
- **Signing/Verification**: Digital signature scheme
- **Nonce Generation**: Secure random nonce generation
- **Storage**: Key-value storage for device keys, tokens, nonces, etc.
- **Encoding**: Message serialization/deserialization
- **Timestamping**: Timestamp generation and validation

### What Implementations Must Implement

**Client Implementations** must support:
- Account creation, recovery, deletion
- Device linking/unlinking
- Authentication (two-phase)
- Access requests with token management
- Key rotation (authentication and access keys)

**Server Implementations** must support:
- Account management endpoints
- Device management endpoints
- Authentication challenge/response
- Token generation and validation
- Access request verification

## Testing Strategy

### Unit Tests
Each implementation should have comprehensive unit tests covering:
- Message serialization/deserialization
- Cryptographic operations
- Storage operations
- Protocol logic

### Integration Tests
Integration tests verify cross-language interoperability:
- TypeScript client → Go server
- TypeScript client → Python server
- TypeScript client → Ruby server
- Python client → Go server
- Etc.

The `scripts/run-integration-tests.sh` script in this repository coordinates integration testing across implementations.

## Getting Started with Development

### Initial Clone

Clone the repository with all submodules:

```bash
git clone --recurse-submodules git@github.com:jasoncolburne/better-auth.git
cd better-auth
```

If you've already cloned without `--recurse-submodules`, initialize them:

```bash
git submodule update --init --recursive
```

### Setup All Implementations

Run the setup script to install dependencies in all implementations and install git hooks:

```bash
./scripts/run-setup.sh
```

This will:
- Run `make setup` in each implementation (installs dependencies, creates Python venv)
- Install git hooks from `scripts/hooks/` to `.git/hooks/`
- Skip implementations where required tooling is not available (Swift, Kotlin, Dart)

### Updating Submodules

To pull the latest changes from the `main` branch in all submodules:

```bash
./scripts/pull-repos.sh
```

This script intelligently:
- Only pulls submodules that are on the `main` branch
- Skips submodules on feature branches (with warning)
- Skips submodules in detached HEAD state (with warning)
- Shows summary of updated/skipped repos

### Running Tests

Each orchestration script runs the corresponding `make` target across all implementations:

```bash
./scripts/run-type-checks.sh    # make type-check
./scripts/run-unit-tests.sh     # make test
./scripts/run-lints.sh          # make lint
./scripts/run-format-checks.sh  # make format-check
./scripts/run-integration-tests.sh  # Starts servers, runs integration tests
./scripts/run-all-checks.sh     # Runs all checks in sequence
```

Scripts gracefully skip implementations where tooling is not available (for some toolchains).

## Git Hooks

### Pre-Commit Hook

The repository includes a pre-commit hook that **prevents committing to the parent repository when any submodule is not on the main branch**. This is critical because:

1. Git submodules record specific commit hashes
2. If you commit while a submodule is on a feature branch or in detached HEAD state, the parent repo will point to that commit
3. Other developers may not be able to access that commit (if the branch isn't pushed, gets deleted, or is unreachable)
4. This breaks reproducible builds and collaboration

### Hook Behavior

The pre-commit hook checks all submodules and:
- ✅ Allows commit if all submodules are on `main` branch
- ❌ Blocks commit if any submodule is on a feature branch
- ❌ Blocks commit if any submodule is in detached HEAD state
- Shows clear error message listing which submodules are problematic

### Hook Installation

Hooks are automatically installed by `./scripts/run-setup.sh`.

To manually install or update hooks:

```bash
./scripts/install-hooks.sh
```

The hooks are version-controlled in `scripts/hooks/` and symlinked to `.git/hooks/`.

### Overriding the Hook

If you have a specific reason to commit while submodules are on feature branches:

```bash
git commit --no-verify -m "message"
```

**Warning:** Only do this if you understand the implications. Generally, the correct workflow is to merge the feature branch to main in the submodule first, then commit to the parent repo.

## Making Changes Across Implementations

### Protocol Changes

When making protocol-level changes:
1. Update the specification in this repository's README
2. If necessary, update the reference implementation (better-auth-ts) - sometimes this will be done by a human
3. Update examples in this README using the reference implementation
4. Propagate changes to other implementations
5. Update integration tests
6. Verify all implementations pass tests

### Implementation-Specific Changes

When making changes to a specific implementation:
- Ensure changes maintain protocol compatibility
- Update that implementation's tests
- Run integration tests to verify interoperability

### Working with Submodules

**Recommended Workflow:**

1. **Work on feature branches in submodules as usual:**
   ```bash
   cd implementations/better-auth-ts
   git checkout -b feature/my-feature
   # make changes, commit
   ```

2. **When ready to integrate, merge to main in the submodule:**
   ```bash
   # In the submodule
   git checkout main
   git merge feature/my-feature
   git push origin main
   ```

3. **Then update the parent repository:**
   ```bash
   # Back in the parent repo
   cd ../..
   git add implementations/better-auth-ts
   git commit -m "Update better-auth-ts: implement my feature"
   ```

**Important Notes:**

- The pre-commit hook will block step 3 if you forget step 2
- Always push the submodule changes before pushing the parent repo
- If others need to access your changes, the submodule commits must be on main
- Using `git commit --no-verify` to bypass the hook is **not recommended** unless you have a specific reason and understand the implications

**Updating Parent Repo Submodule References:**

After pulling changes in a submodule:
```bash
cd implementations/better-auth-ts
git pull origin main
cd ../..
git add implementations/better-auth-ts
git commit -m "Update better-auth-ts to latest"
```

Or use the automated script if all submodules are on main:
```bash
./scripts/pull-repos.sh  # Pulls all submodules on main
git add implementations/
git commit -m "Update all implementations to latest"
```

## Repository Structure

This spec repository contains:

### Core Documentation
- `README.md`: Complete protocol specification with examples
- `CLAUDE.md`: This file - development guidelines and architecture

### Implementation Submodules
- `implementations/`: Git submodules for all 8 implementations
  - `implementations/better-auth-ts/` - TypeScript (reference implementation)
  - `implementations/better-auth-py/` - Python
  - `implementations/better-auth-go/` - Go
  - `implementations/better-auth-rb/` - Ruby
  - `implementations/better-auth-rs/` - Rust
  - `implementations/better-auth-swift/` - Swift
  - `implementations/better-auth-dart/` - Dart
  - `implementations/better-auth-kt/` - Kotlin

### Orchestration Scripts
- `scripts/pull-repos.sh`: Update all submodules (only pulls if on `main` branch)
- `scripts/run-setup.sh`: Setup all implementations + install git hooks
- `scripts/run-type-checks.sh`: Run type checkers across implementations
- `scripts/run-unit-tests.sh`: Run unit tests across implementations
- `scripts/run-lints.sh`: Run linters across implementations
- `scripts/run-format-checks.sh`: Run format checkers across implementations
- `scripts/run-integration-tests.sh`: Run integration tests (all client/server combinations)
- `scripts/run-all-checks.sh`: Master script to run all checks

### Git Hooks
- `scripts/hooks/pre-commit`: Pre-commit hook (version controlled)
- `scripts/install-hooks.sh`: Install git hooks to `.git/hooks/`

### Standardized Makefiles
Each implementation has a Makefile with common targets:
- `make setup`: Install dependencies (creates venv for Python)
- `make test`: Run unit tests
- `make type-check`: Run type checker
- `make lint`: Run linter
- `make format`: Auto-format code
- `make format-check`: Check code formatting
- `make clean`: Clean build artifacts
- `make server`: Start development server (server implementations only)
- `make test-integration`: Run integration tests (client implementations only)
- `make build`: Build project (where applicable)

## Development Status

The protocol specification is functional but **not yet formally reviewed**.

The TypeScript implementation is the most mature. Other implementations (Go, Python, Ruby, Rust, Swift, Dart, Kotlin) were created with assistance from Claude and have basic functionality but need polish and thorough review.

## Future Work

- Formal security review of the protocol
- Performance benchmarking across implementations
- Extended attribute system for fine-grained permissions
- Additional example implementations
- Comprehensive documentation per implementation
