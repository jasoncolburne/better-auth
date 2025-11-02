# Better Auth Error Specification

This document defines the standardized error taxonomy for all Better Auth implementations. All implementations MUST implement these error types with consistent naming, codes, and messages.

## Error Hierarchy

```
BetterAuthError (base)
├── ValidationError
│   ├── InvalidMessageError
│   ├── InvalidIdentityError
│   ├── InvalidDeviceError
│   └── InvalidHashError
├── CryptographicError
│   └── IncorrectNonceError
├── AuthenticationError
│   └── MismatchedIdentitiesError
├── TokenError
│   ├── ExpiredTokenError
│   └── FutureTokenError
└── TemporalError
    ├── StaleRequestError
    └── FutureRequestError
```

## Error Catalog

### Base Error

#### BetterAuthError
- **Code**: `BA000`
- **Category**: Base
- **Message**: Base class for all Better Auth errors
- **Context**: All errors inherit from this
- **Usage**: Never thrown directly, only used as base class

---

## Validation Errors

### InvalidMessageError
- **Code**: `BA101`
- **Category**: Validation
- **Message**: "Message structure is invalid or malformed"
- **Context**:
  - Field name that is missing/invalid
  - Expected structure
- **Common Causes**:
  - Missing required fields (payload, signature, nonce)
  - Null/undefined values where required
  - Message too short/too long
  - Invalid JSON structure
- **Old Messages**: "payload not defined", "null signature", "message too short"

### InvalidIdentityError
- **Code**: `BA102`
- **Category**: Validation
- **Message**: "Identity verification failed"
- **Context**:
  - Provided identity
  - Expected identity format
- **Common Causes**:
  - Identity string doesn't match cryptographic material
  - Identity format invalid
  - Identity hash derivation failed

### InvalidDeviceError
- **Code**: `BA103`
- **Category**: Validation
- **Message**: "Device hash does not match hash(publicKey || rotationHash)"
- **Context**:
  - Provided device hash
  - Calculated device hash
  - Public key
  - Rotation hash
- **Common Causes**:
  - Device derivation incorrect
  - Device not found in storage
  - Device revoked/disabled
- **Old Messages**: "bad device derivation"

### InvalidHashError
- **Code**: `BA104`
- **Category**: Validation
- **Message**: "Hash validation failed"
- **Context**:
  - Expected hash
  - Actual hash
  - Hash type (rotation, recovery, etc.)
- **Common Causes**:
  - Rotation hash doesn't match hash(nextPublicKey)
  - Recovery hash doesn't match hash(recoveryPublicKey)
  - Invalid hash format
- **Old Messages**: "hash mismatch"

---

## Cryptographic Errors

### IncorrectNonceError
- **Code**: `BA203`
- **Category**: Cryptographic
- **Message**: "Response nonce does not match request nonce"
- **Context**:
  - Expected nonce (from request)
  - Actual nonce (from response)
- **Common Causes**:
  - Server returned wrong nonce
  - Request/response mismatch
  - Network corruption
- **Old Messages**: "incorrect nonce"

---

## Authentication/Authorization Errors

### MismatchedIdentitiesError
- **Code**: `BA302`
- **Category**: Authentication
- **Message**: "Link container identity does not match request identity"
- **Context**:
  - Link container identity
  - Request identity
- **Common Causes**:
  - Attempt to link device for wrong identity
  - Man-in-the-middle attack
  - Protocol implementation bug
- **Old Messages**: "mismatched identities"

---

## Token Errors

### ExpiredTokenError
- **Code**: `BA401`
- **Category**: Token
- **Message**: "Token has expired"
- **Context**:
  - Token expiry time
  - Current time
  - Token type (access/refresh)
- **Common Causes**:
  - Access token past `expires_at`
  - Refresh window closed
  - Token not refreshed in time
- **Old Messages**: "token expired", "refresh has expired"

### FutureTokenError
- **Code**: `BA403`
- **Category**: Token
- **Message**: "Token issued_at timestamp is in the future"
- **Context**:
  - Token `issued_at`
  - Current time
  - Time difference
- **Common Causes**:
  - Server clock ahead of client
  - Clock skew between systems
  - Malicious token injection
- **Old Messages**: "token from future"

---

## Temporal Errors

### StaleRequestError
- **Code**: `BA501`
- **Category**: Temporal
- **Message**: "Request timestamp is too old"
- **Context**:
  - Request timestamp
  - Current time
  - Maximum age allowed
- **Common Causes**:
  - Request took too long to arrive
  - Clock skew
  - Replay attack with old request
- **Old Messages**: "stale request"

### FutureRequestError
- **Code**: `BA502`
- **Category**: Temporal
- **Message**: "Request timestamp is in the future"
- **Context**:
  - Request timestamp
  - Current time
  - Time difference
- **Common Causes**:
  - Client clock ahead of server
  - Clock skew between systems
  - Malicious request injection
- **Old Messages**: "request from future"

---

## Implementation Guidelines

### Language-Specific Conventions

#### TypeScript/JavaScript
```typescript
class BetterAuthError extends Error {
  code: string;
  context?: Record<string, any>;

  constructor(message: string, code: string, context?: Record<string, any>) {
    super(message);
    this.name = this.constructor.name;
    this.code = code;
    this.context = context;
  }
}

class InvalidDeviceError extends BetterAuthError {
  constructor(provided: string, calculated: string) {
    super(
      "Device hash does not match hash(publicKey || rotationHash)",
      "BA103",
      { provided, calculated }
    );
  }
}

// Usage
throw new InvalidDeviceError(providedDevice, calculatedDevice);
```

#### Python
```python
class BetterAuthError(Exception):
    """Base exception for Better Auth"""
    error_code: str = "BA000"

    def __init__(self, message: str, context: dict | None = None):
        super().__init__(message)
        self.context = context or {}

class InvalidDeviceError(BetterAuthError):
    """Device hash validation failed"""
    error_code = "BA103"

    def __init__(self, provided: str, calculated: str):
        super().__init__(
            "Device hash does not match hash(publicKey || rotationHash)",
            context={"provided": provided, "calculated": calculated}
        )

# Usage
raise InvalidDeviceError(provided_device, calculated_device)
```

#### Rust
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum BetterAuthError {
    #[error("Message structure is invalid or malformed")]
    InvalidMessage { field: String },

    #[error("Device hash does not match hash(publicKey || rotationHash)")]
    InvalidDevice { provided: String, calculated: String },

    // ... etc
}

impl BetterAuthError {
    pub fn code(&self) -> &str {
        match self {
            Self::InvalidMessage { .. } => "BA101",
            Self::InvalidDevice { .. } => "BA103",
            // ... etc
        }
    }
}

// Usage
return Err(BetterAuthError::InvalidDevice {
    provided: provided_device,
    calculated: calculated_device,
});
```

#### Go
```go
package betterauth

import "fmt"

type ErrorCode string

const (
    ErrCodeInvalidMessage ErrorCode = "BA101"
    ErrCodeInvalidDevice  ErrorCode = "BA103"
    // ... etc
)

type BetterAuthError struct {
    Code    ErrorCode
    Message string
    Context map[string]interface{}
    Err     error
}

func (e *BetterAuthError) Error() string {
    return fmt.Sprintf("[%s] %s", e.Code, e.Message)
}

func NewInvalidDeviceError(provided, calculated string) *BetterAuthError {
    return &BetterAuthError{
        Code:    ErrCodeInvalidDevice,
        Message: "Device hash does not match hash(publicKey || rotationHash)",
        Context: map[string]interface{}{
            "provided":   provided,
            "calculated": calculated,
        },
    }
}

// Usage
return nil, NewInvalidDeviceError(providedDevice, calculatedDevice)
```

#### Ruby
```ruby
module BetterAuth
  class Error < StandardError
    attr_reader :code, :context

    def initialize(message, code, context = {})
      super(message)
      @code = code
      @context = context
    end
  end

  class InvalidDeviceError < Error
    def initialize(provided, calculated)
      super(
        "Device hash does not match hash(publicKey || rotationHash)",
        "BA103",
        { provided: provided, calculated: calculated }
      )
    end
  end
end

# Usage
raise BetterAuth::InvalidDeviceError.new(provided_device, calculated_device)
```

#### Swift
```swift
enum BetterAuthError: Error {
    case invalidMessage(field: String)
    case invalidDevice(provided: String, calculated: String)
    // ... etc

    var code: String {
        switch self {
        case .invalidMessage: return "BA101"
        case .invalidDevice: return "BA103"
        // ... etc
        }
    }

    var message: String {
        switch self {
        case .invalidMessage(let field):
            return "Message structure is invalid: \(field)"
        case .invalidDevice:
            return "Device hash does not match hash(publicKey || rotationHash)"
        // ... etc
        }
    }
}

// Usage
throw BetterAuthError.invalidDevice(provided: providedDevice, calculated: calculatedDevice)
```

#### Dart
```dart
class BetterAuthError implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? context;

  BetterAuthError(this.code, this.message, [this.context]);

  @override
  String toString() => '[$code] $message';
}

class InvalidDeviceError extends BetterAuthError {
  InvalidDeviceError(String provided, String calculated)
      : super(
          'BA103',
          'Device hash does not match hash(publicKey || rotationHash)',
          {'provided': provided, 'calculated': calculated},
        );
}

// Usage
throw InvalidDeviceError(providedDevice, calculatedDevice);
```

#### Kotlin
```kotlin
sealed class BetterAuthError(
    val code: String,
    override val message: String,
    val context: Map<String, Any> = emptyMap()
) : Exception(message) {

    class InvalidMessage(field: String) : BetterAuthError(
        "BA101",
        "Message structure is invalid or malformed",
        mapOf("field" to field)
    )

    class InvalidDevice(provided: String, calculated: String) : BetterAuthError(
        "BA103",
        "Device hash does not match hash(publicKey || rotationHash)",
        mapOf("provided" to provided, "calculated" to calculated)
    )

    // ... etc
}

// Usage
throw BetterAuthError.InvalidDevice(providedDevice, calculatedDevice)
```

---

## Error Response Format

All implementations should return errors in a consistent format over the network:

### JSON Format
```json
{
  "error": {
    "code": "BA103",
    "message": "Device hash does not match hash(publicKey || rotationHash)",
    "context": {
      "provided": "a1b2c3d4...",
      "calculated": "e5f6g7h8..."
    }
  }
}
```

### HTTP Status Codes

Map error categories to HTTP status codes:

- **400 Bad Request**: Validation errors, invalid message
- **401 Unauthorized**: Authentication errors, expired tokens
- **422 Unprocessable Entity**: Temporal errors (stale request, future timestamps)
- **500 Internal Server Error**: Unexpected protocol errors

---

## Testing Requirements

Each implementation MUST have tests for:

1. **Error instantiation**: Each error type can be created with appropriate context
2. **Error codes**: Each error has correct error code
3. **Error messages**: Messages are correct and include context
4. **Error hierarchy**: Subclass relationships are correct
5. **Error serialization**: Errors serialize to JSON correctly
6. **Error handling**: Proper error handling in all protocol operations

Example test structure:
```python
def test_invalid_device_error():
    error = InvalidDeviceError("provided_hash", "calculated_hash")
    assert error.error_code == "BA103"
    assert "Device hash" in str(error)
    assert error.context["provided"] == "provided_hash"
    assert error.context["calculated"] == "calculated_hash"
```

---

## Version History

- **v1.0.0** (2025-11-01): Initial error specification
  - Defined 10 error types across 5 categories
  - Standardized error codes (BA001-BA999)
  - Added context requirements for debugging
  - Provided language-specific implementation patterns
