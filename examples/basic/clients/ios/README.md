# Better Auth iOS Example App

A basic iOS application demonstrating the Better Auth Swift client implementation.

## Project Structure

```
BetterAuthBasicExample/
├── BetterAuthBasicExampleApp.swift   # App entry point
├── ContentView.swift                  # Main UI with createAccount button
├── PlaceholderImplementations.swift   # Complete interface implementations
└── Assets.xcassets/                   # App assets
```

## Features

- SwiftUI-based iOS app
- Single button that calls `betterAuthClient.createAccount()`
- Complete interface implementations including:
  - `Secp256r1` signing key (P-256 elliptic curve)
  - `ClientRotatingKeyStore` for key rotation
  - `Hasher` using BLAKE3
  - `Noncer` for nonce generation
  - `Rfc3339Nano` timestamper
  - `PlaceholderNetwork` for HTTP requests
  - All required storage implementations

## Dependencies

The app uses the following Swift packages:
- `better-auth-swift` (local package)
- `BLAKE3` for cryptographic hashing
- `swift-crypto` for P-256 signing

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

1. The app creates a `BetterAuthClient` with all required interface implementations
2. When the button is tapped, it:
   - Generates a recovery key (Secp256r1)
   - Computes the recovery hash using BLAKE3
   - Calls `betterAuthClient.createAccount(recoveryHash)`
3. The client will attempt to make an HTTP request to the server (default: http://localhost:3000)
4. Results are displayed in the UI

## Interface Implementations

All implementations are in `PlaceholderImplementations.swift` and are fully functional:

- **Crypto**: Secp256r1 (P-256), BLAKE3 hashing, secure random nonces
- **Storage**: In-memory key-value stores for client state
- **Network**: URLSession-based HTTP client
- **Timestamping**: RFC3339 with fractional seconds

The only "placeholder" is the network implementation which needs a running server.

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
