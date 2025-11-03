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

## Error Handling at Library Boundaries

**CRITICAL REQUIREMENT**: All implementations MUST preserve error structure (code, message, and context) at the library boundary. Users of Better Auth libraries must be able to:

1. **Programmatically distinguish error types** by inspecting error codes
2. **Access structured context** for debugging and logging
3. **Serialize errors to JSON** for transmission or storage
4. **Pattern match or type-check** errors for specific handling

### Anti-Patterns to Avoid

❌ **Converting errors to plain strings at the library boundary**
```rust
// WRONG: Loses all structure
pub fn create_account(&self) -> Result<String, String>

impl From<BetterAuthError> for String {
    fn from(err: BetterAuthError) -> String {
        err.message  // Loses code and context!
    }
}
```

❌ **Throwing generic string errors**
```typescript
// WRONG: Cannot be caught specifically
throw "device validation failed"
```

❌ **Wrapping structured errors in generic wrappers without preserving original**
```python
# WRONG: Loses original error information
except BetterAuthError as e:
    raise Exception(str(e))
```

### Correct Patterns

✅ **Preserve full error structure**
```rust
// CORRECT: Returns structured error
pub fn create_account(&self) -> Result<String, BetterAuthError>
```

✅ **Use typed exceptions/errors**
```typescript
// CORRECT: Can be caught and inspected
throw new InvalidDeviceError(provided, calculated)
```

✅ **Enable type-based error handling**
```go
// CORRECT: Callers can type-assert to access context
func CreateAccount() (string, error) {
    return "", errors.NewInvalidDeviceError(provided, calculated)
}

// Caller can then:
if betterErr, ok := err.(*errors.BetterAuthError); ok {
    log.Printf("Error code: %s, context: %v", betterErr.Code, betterErr.Context)
}
```

### Verification Checklist

All implementations should verify:

- [ ] Public API methods return/throw structured error types (not strings)
- [ ] Error codes are accessible to library users
- [ ] Error context is accessible to library users
- [ ] Errors can be serialized to JSON without loss of information
- [ ] Language-idiomatic error handling patterns work correctly
- [ ] Integration tests verify error context preservation

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
use serde::{Serialize, Deserialize};
use std::collections::HashMap;
use std::fmt;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BetterAuthError {
    pub code: &'static str,
    pub message: String,
    pub context: HashMap<String, String>,
}

impl fmt::Display for BetterAuthError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "[{}] {}", self.code, self.message)
    }
}

impl std::error::Error for BetterAuthError {}

// Factory functions for each error type
pub fn invalid_device_error(provided: &str, calculated: &str) -> BetterAuthError {
    let mut context = HashMap::new();
    context.insert("provided".to_string(), provided.to_string());
    context.insert("calculated".to_string(), calculated.to_string());

    BetterAuthError {
        code: "BA103",
        message: "Device hash does not match hash(publicKey || rotationHash)".to_string(),
        context,
    }
}

// Public API MUST return Result<T, BetterAuthError> not Result<T, String>
pub async fn create_account(&self, message: &str) -> Result<String, BetterAuthError> {
    // ... implementation
    Err(invalid_device_error(&provided, &calculated))
}

// DO NOT implement From<BetterAuthError> for String - it loses information!
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

## How to Handle Better Auth Errors

This section shows library users how to properly catch and inspect Better Auth errors in each language.

### TypeScript/JavaScript

```typescript
import { BetterAuthClient, InvalidDeviceError, ExpiredTokenError } from 'better-auth';

const client = new BetterAuthClient(/* ... */);

try {
  await client.createAccount(recoveryHash);
} catch (error) {
  // Check for specific error types
  if (error instanceof InvalidDeviceError) {
    console.error('Device validation failed:', error.context);
    console.error('Provided:', error.context.provided);
    console.error('Calculated:', error.context.calculated);
  } else if (error instanceof ExpiredTokenError) {
    console.error('Token expired at:', error.context.expiresAt);
    // Trigger re-authentication
  }

  // Access error code and message
  console.error(`Error [${error.code}]: ${error.message}`);

  // Serialize for logging
  console.error(JSON.stringify(error.toJSON()));
}
```

### Python

```python
from better_auth import BetterAuthClient, InvalidDeviceError, ExpiredTokenError

client = BetterAuthClient(...)

try:
    await client.create_account(recovery_hash)
except InvalidDeviceError as e:
    print(f"Device validation failed: {e.context}")
    print(f"Provided: {e.context['provided']}")
    print(f"Calculated: {e.context['calculated']}")
except ExpiredTokenError as e:
    print(f"Token expired at: {e.context['expires_at']}")
    # Trigger re-authentication
except BetterAuthError as e:
    # Catch all Better Auth errors
    print(f"Error [{e.error_code}]: {str(e)}")
    print(f"Context: {e.context}")

    # Serialize for logging
    print(e.to_dict())
```

### Rust

```rust
use better_auth::{BetterAuthClient, BetterAuthError};

let client = BetterAuthClient::new(/* ... */);

match client.create_account(&message).await {
    Ok(response) => {
        // Handle success
    }
    Err(err) => {
        // Pattern match on error code
        match err.code {
            "BA103" => {
                // InvalidDevice
                eprintln!("Device validation failed");
                if let Some(provided) = err.context.get("provided") {
                    eprintln!("Provided: {}", provided);
                }
                if let Some(calculated) = err.context.get("calculated") {
                    eprintln!("Calculated: {}", calculated);
                }
            }
            "BA401" => {
                // ExpiredToken
                eprintln!("Token expired");
                // Trigger re-authentication
            }
            _ => {
                eprintln!("Error [{}]: {}", err.code, err.message);
            }
        }

        // Serialize for logging
        if let Ok(json) = serde_json::to_string(&err) {
            eprintln!("Error JSON: {}", json);
        }
    }
}
```

### Go

```go
import (
    "fmt"
    "github.com/jasoncolburne/better-auth-go/pkg/client"
    "github.com/jasoncolburne/better-auth-go/pkg/errors"
)

c := client.NewBetterAuthClient(/* ... */)

response, err := c.CreateAccount(ctx, message)
if err != nil {
    // Type assert to BetterAuthError to access structured fields
    if betterErr, ok := err.(*errors.BetterAuthError); ok {
        switch betterErr.Code {
        case errors.CodeInvalidDevice:
            fmt.Printf("Device validation failed\n")
            fmt.Printf("Provided: %v\n", betterErr.Context["provided"])
            fmt.Printf("Calculated: %v\n", betterErr.Context["calculated"])
        case errors.CodeExpiredToken:
            fmt.Printf("Token expired at: %v\n", betterErr.Context["expiresAt"])
            // Trigger re-authentication
        default:
            fmt.Printf("Error [%s]: %s\n", betterErr.Code, betterErr.Message)
        }

        // Serialize for logging
        if jsonBytes, err := json.Marshal(betterErr); err == nil {
            fmt.Printf("Error JSON: %s\n", jsonBytes)
        }
    } else {
        // Handle unexpected error types
        fmt.Printf("Unexpected error: %v\n", err)
    }
}
```

### Ruby

```ruby
require 'better_auth'

client = BetterAuth::Client.new(...)

begin
  client.create_account(recovery_hash)
rescue BetterAuth::InvalidDeviceError => e
  puts "Device validation failed: #{e.context}"
  puts "Provided: #{e.context[:provided]}"
  puts "Calculated: #{e.context[:calculated]}"
rescue BetterAuth::ExpiredTokenError => e
  puts "Token expired at: #{e.context[:expires_at]}"
  # Trigger re-authentication
rescue BetterAuth::Error => e
  # Catch all Better Auth errors
  puts "Error [#{e.code}]: #{e.message}"
  puts "Context: #{e.context}"

  # Serialize for logging
  puts e.to_json
end
```

### Swift

```swift
import BetterAuth

let client = BetterAuthClient(/* ... */)

do {
    try await client.createAccount(recoveryHash)
} catch let error as BetterAuthError {
    switch error.code {
    case "BA103": // InvalidDevice
        print("Device validation failed")
        if let provided = error.context?["provided"] {
            print("Provided: \(provided)")
        }
        if let calculated = error.context?["calculated"] {
            print("Calculated: \(calculated)")
        }
    case "BA401": // ExpiredToken
        print("Token expired")
        // Trigger re-authentication
    default:
        print("Error [\(error.code)]: \(error.message)")
    }

    // Serialize for logging
    if let jsonData = try? JSONEncoder().encode(error),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        print("Error JSON: \(jsonString)")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

### Dart

```dart
import 'package:better_auth/better_auth.dart';

final client = BetterAuthClient(/* ... */);

try {
  await client.createAccount(recoveryHash);
} on InvalidDeviceError catch (e) {
  print('Device validation failed: ${e.context}');
  print('Provided: ${e.context['provided']}');
  print('Calculated: ${e.context['calculated']}');
} on ExpiredTokenError catch (e) {
  print('Token expired at: ${e.context['expiresAt']}');
  // Trigger re-authentication
} on BetterAuthError catch (e) {
  // Catch all Better Auth errors
  print('Error [${e.code}]: ${e.message}');
  print('Context: ${e.context}');

  // Serialize for logging
  print(jsonEncode(e.toJson()));
}
```

### Kotlin

```kotlin
import com.betterauth.BetterAuthClient
import com.betterauth.BetterAuthError

val client = BetterAuthClient(/* ... */)

try {
    client.createAccount(recoveryHash)
} catch (e: BetterAuthError) {
    when (e) {
        is BetterAuthError.InvalidDevice -> {
            println("Device validation failed")
            println("Provided: ${e.context["provided"]}")
            println("Calculated: ${e.context["calculated"]}")
        }
        is BetterAuthError.ExpiredToken -> {
            println("Token expired at: ${e.context["expiresAt"]}")
            // Trigger re-authentication
        }
        else -> {
            println("Error [${e.code}]: ${e.message}")
            println("Context: ${e.context}")
        }
    }

    // Serialize for logging
    println(e.toJson())
}
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
