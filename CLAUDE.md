# Better Auth - Protocol Specification

## Project Overview

Better Auth is a **multi-repository, multi-language authentication protocol** spanning 9 repositories:
- 1 specification repository (this one)
- 8 implementation repositories across different languages

This is the **specification repository** that defines the core protocol. All implementations follow this spec.

## Multi-Repository Architecture

Typically, the implementations are in adjacent directories (eg ../better-auth-ts) and scanning github is not required.

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
4. **Rotations are protected using forward secrecy**

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

### Forward Secrecy via Key Rotation

Keys are rotated by:
1. Pre-committing to the next key using a hash (rotationHash)
2. When rotating, revealing the key that matches the previous hash
3. Establishing a new rotationHash for the next rotation

This creates a hash chain that provides forward secrecy - compromising the current key doesn't reveal other keys
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

The `run-integration-tests.sh` script in this repository coordinates integration testing across implementations.

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

## Repository Structure

This spec repository contains:
- `README.md`: Complete protocol specification with examples
- `run-integration-tests.sh`: Integration test orchestration
- `run-unit-tests.sh`: Unit test runner for all implementations
- `run-lints.sh`: Lint runner for all implementations
- `run-format-checks.sh`: Format checker for all implementations
- `run-all-checks.sh`: Master script to run all checks

## Development Status

The protocol specification is functional but **not yet formally reviewed**.

The TypeScript implementation is the most mature. Other implementations (Go, Python, Ruby, Rust, Swift, Dart, Kotlin) were created with assistance from Claude and have basic functionality but need polish and thorough review.

## Future Work

- Formal security review of the protocol
- Performance benchmarking across implementations
- Extended attribute system for fine-grained permissions
- Additional example implementations
- Comprehensive documentation per implementation
