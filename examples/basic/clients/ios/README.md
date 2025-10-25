# Better Auth iOS Example App

A basic iOS application demonstrating the Better Auth Swift client implementation.

## Project Structure

```
BetterAuthBasicExample/
├── BetterAuthBasicExampleApp.swift   # App entry point
├── ContentView.swift                  # Main UI with state management
├── Implementation/
│   ├── PlaceholderImplementations.swift  # Complete interface implementations
│   └── Views/
│       ├── Logic.swift                   # Business logic and API interactions
│       ├── ReadyStateView.swift          # UI for ready state (create/link/recover)
│       ├── CreatedStateView.swift        # UI for created state (session/device mgmt)
│       ├── AuthenticatedStateView.swift  # UI for authenticated state (access requests)
│       ├── BottomSheetInputView.swift    # Reusable bottom sheet for inputs
│       └── LinkDevicePromptView.swift    # Device linking interface
└── Assets.xcassets/                   # App assets
```

## Features

### Full Authentication Flow
- **Account Management**: Create, recover, and delete accounts
- **Device Management**: Link/unlink devices, rotate device credentials
- **Session Management**: Create, refresh, and end sessions
- **Access Requests**: Test authenticated requests to multiple app servers
- **Recovery System**: Argon2id-based passphrase recovery with automatic clipboard management

### UI Design
- Three distinct states (Ready, Created, Authenticated) with state-specific actions
- Bottom sheet input trays for clean, button-focused main UI
- Automatic state inference from keychain on app launch
- Real-time status messages and loading indicators
- Identity/device identifiers with tap-to-copy functionality

### Complete Interface Implementations
- **Hardware-backed keys**: `HardwareSecp256r1` for authentication and access keys (P-256 elliptic curve)
  - Uses iOS Secure Enclave on real devices
  - Falls back to hardware-backed keychain storage on simulator
- **Software keys**: `Secp256r1` for recovery keys derived from passphrases
- `ClientRotatingKeyStore` for key rotation with forward secrecy
- `Hasher` using BLAKE3
- `Noncer` for secure nonce generation
- `Rfc3339Nano` timestamper (ISO8601 with millisecond precision)
- `Network` implementation with URLSession
- `Argon2` password hashing using native C library
- `Passphrase` generation (24-word passphrases)
- All required storage implementations (keychain-based)

## Dependencies

The app uses the following Swift packages and native libraries:
- `better-auth-swift` (local package)
- `BLAKE3` for cryptographic hashing
- `swift-crypto` for P-256 signing
- `phc-winner-argon2` (git submodule) for Argon2id password hashing

## Building and Running

### Option 1: Using Xcode (Recommended if your xcodebuild is working)

```bash
make simulator
```

This will open the project in Xcode where you can select a simulator and run it.

### Option 2: Command Line (if xcodebuild is working)

```bash
# Build the app
make build

# Build and run in simulator
make simulator

# Use a different simulator
make simulator SIMULATOR_NAME='iPhone 15'
```

### Current Issue

Your system has an xcodebuild plugin issue:
```
DVTPlugInLoading: Failed to load code for plug-in com.apple.dt.IDESimulatorFoundation
```

To fix this, you may need to:
1. Run `xcodebuild -runFirstLaunch`
2. Update Xcode command line tools: `sudo xcode-select --install`
3. Or reinstall Xcode

## How It Works

### State Management

The app manages three distinct states based on keychain contents:

1. **Ready State** (no credentials stored)
   - Create new account
   - Link this device to existing account
   - Recover account with passphrase

2. **Created State** (authentication credentials stored)
   - Create session (authenticate)
   - Link another device
   - Unlink device
   - Rotate device credentials
   - Change recovery passphrase
   - Erase credentials
   - Delete account

3. **Authenticated State** (access credentials stored)
   - Refresh session
   - End session
   - Test app servers (make authenticated requests)

### Key Flows

**Account Creation**:
1. Generates a 24-word passphrase using BIP39-style word list
2. Derives 32-byte seed from passphrase using Argon2id
3. Seeds a Secp256r1 recovery key with the derived bytes
4. Hashes the recovery public key using BLAKE3
5. Calls `betterAuthClient.createAccount(recoveryHash)`
6. Copies passphrase to clipboard for safekeeping

**Device Linking**:
1. Existing device generates link container with endorsement
2. Link container copied to clipboard
3. New device pastes and submits link container
4. Server validates both device signatures
5. New device is linked to the account

**Recovery**:
1. User provides identity and recovery passphrase
2. App derives recovery key from passphrase
3. Generates new recovery passphrase/key for rotation
4. Calls `betterAuthClient.recoverAccount(identity, recoveryKey, nextRecoveryHash)`
5. All other devices are unlinked
6. New passphrase copied to clipboard

**Authentication**:
1. Two-phase process: RequestSession → CreateSession
2. Client requests challenge nonce from server
3. Client signs nonce with device key
4. Server issues access token
5. Access token stored for subsequent requests

### Bottom Sheet Input Pattern

All text inputs use bottom sheet trays that:
- Slide up from the bottom when button is tapped
- Present inputs with clear labels and action buttons
- Automatically dismiss after submission
- Clear inputs when sheet appears (not after submission to avoid race conditions)
- Use consistent rounded corner styling throughout

## Interface Implementations

All implementations are in `Implementation/` directory and are fully functional:

- **Crypto**:
  - `HardwareSecp256r1` for authentication/access keys using Secure Enclave (real devices) or hardware keychain (simulator)
  - `Secp256r1` software implementation for recovery keys derived from passphrases
  - BLAKE3 hashing
  - Argon2id password hashing
  - Secure random nonces
- **Storage**: Keychain-based persistent storage for keys and tokens
- **Network**: URLSession-based HTTP client
- **Timestamping**: RFC3339/ISO8601 with fractional seconds (millisecond precision)
- **Passphrase**: 24-word passphrase generation from BIP39-style word list

The network implementation assumes the existence of the basic example Better Auth deployment served from localhost.

## Next Steps

1. Fix the xcodebuild plugin issue on your system
2. Start a Better Auth server (Go, Ruby, TypeScript, Python, or Rust)
3. Update `PlaceholderNetwork` baseURL if needed
4. Run the app and test account creation

## Makefile Targets

```bash
make simulator        # Build and run in simulator
make build            # Build the app
make clean            # Clean build artifacts
make list-simulators  # List available iOS simulators
make help             # Show help message
```
