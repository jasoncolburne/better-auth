import Foundation
import BetterAuth
import Crypto
import BLAKE3

// MARK: - Debug Utilities
func debugPrint(_ items: Any...) {
    let output = items.map { "\($0)" }.joined(separator: " ")
    fputs(output + "\n", stderr)
    fflush(stderr)
}

// MARK: - Base64 Utilities
enum Base64 {
    static func encode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    static func decode(_ base64Str: String) -> Data {
        let normalized = base64Str.replacingOccurrences(of: "_", with: "/").replacingOccurrences(
            of: "-", with: "+"
        )
        return Data(base64Encoded: normalized)!
    }
}

// MARK: - Blake3 Hasher
enum Blake3 {
    static func sum256(_ bytes: Data) async -> Data {
        Data(BLAKE3.hash(contentsOf: bytes))
    }
}

// MARK: - Entropy
func getEntropy(_ length: Int) async -> Data {
    var bytes = [UInt8](repeating: 0, count: length)
    let result = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    guard result == errSecSuccess else {
        fatalError("Failed to generate random bytes")
    }
    return Data(bytes)
}

// MARK: - Secp256r1 Verifier
class Secp256r1Verifier: IVerifier {
    var signatureLength: Int { 88 }

    func verify(_ message: String, _ signature: String, _ publicKey: String) async throws {
        let publicKeyBytes = Base64.decode(publicKey).dropFirst(3)
        let signatureBytes = Base64.decode(signature).dropFirst(2)
        let messageBytes = message.data(using: .utf8)!

        let key = try P256.Signing.PublicKey(compressedRepresentation: publicKeyBytes)
        let sig = try P256.Signing.ECDSASignature(rawRepresentation: signatureBytes)

        guard key.isValidSignature(sig, for: messageBytes) else {
            throw BetterAuthError.invalidData
        }
    }
}

// MARK: - Secp256r1 Signing Key
class Secp256r1: ISigningKey {
    private var keyPair: P256.Signing.PrivateKey?
    private let _verifier = Secp256r1Verifier()

    func generate() async {
        keyPair = P256.Signing.PrivateKey()
    }

    func sign(_ message: String) async throws -> String {
        guard let keyPair else {
            throw BetterAuthError.keypairNotGenerated
        }

        let messageBytes = message.data(using: .utf8)!
        let signature = try keyPair.signature(for: messageBytes)
        let signatureBytes = signature.rawRepresentation

        var paddedBytes = Data([0, 0])
        paddedBytes.append(signatureBytes)
        let base64 = Base64.encode(paddedBytes)

        return "0I" + base64.dropFirst(2)
    }

    func `public`() async throws -> String {
        guard let keyPair else {
            throw BetterAuthError.keypairNotGenerated
        }

        let publicKey = keyPair.publicKey
        let compressed = publicKey.compressedRepresentation

        var paddedBytes = Data([0, 0, 0])
        paddedBytes.append(compressed)
        let base64 = Base64.encode(paddedBytes)

        return "1AAI" + base64.dropFirst(4)
    }

    func verifier() -> any IVerifier {
        _verifier
    }

    func verify(_ message: String, _ signature: String) async throws {
        try await _verifier.verify(message, signature, self.public())
    }
}

// MARK: - Client Rotating Key Store
class ClientRotatingKeyStore: IClientRotatingKeyStore {
    private var currentKey: (any ISigningKey)?
    private var nextKey: (any ISigningKey)?
    private var futureKey: (any ISigningKey)?
    private let hasher = Hasher()

    func initialize(_ extraData: String?) async throws -> (String, String, String) {
        let current = Secp256r1()
        let next = Secp256r1()

        await current.generate()
        await next.generate()

        currentKey = current
        nextKey = next

        let suffix = extraData ?? ""

        let publicKey = try await current.public()
        let rotationHash = try await hasher.sum(next.public())
        let identity = try await hasher.sum(publicKey + rotationHash + suffix)

        return (identity, publicKey, rotationHash)
    }

    func next() async throws -> (any ISigningKey, String) {
        guard let nextKey else {
            throw BetterAuthError.callInitializeFirst
        }

        if futureKey == nil {
            let key = Secp256r1()
            await key.generate()
            futureKey = key
        }

        let rotationHash = try await hasher.sum(futureKey!.public())

        return (nextKey, rotationHash)
    }

    func rotate() async throws {
        guard let nextKey else {
            throw BetterAuthError.callInitializeFirst
        }

        guard let futureKey else {
            throw BetterAuthError.callNextFirst
        }

        currentKey = nextKey
        self.nextKey = futureKey
        self.futureKey = nil
    }

    func signer() async throws -> any ISigningKey {
        guard let currentKey else {
            throw BetterAuthError.callInitializeFirst
        }

        return currentKey
    }
}

// MARK: - Hasher
class Hasher: IHasher {
    func sum(_ message: String) async throws -> String {
        let bytes = message.data(using: .utf8)!
        let hash = await Blake3.sum256(bytes)
        var paddedBytes = Data([0])
        paddedBytes.append(hash)
        let base64 = Base64.encode(paddedBytes)

        return "E" + base64.dropFirst()
    }
}

// MARK: - Noncer
class Noncer: INoncer {
    func generate128() async throws -> String {
        let entropy = await getEntropy(16)

        var paddedBytes = Data([0, 0])
        paddedBytes.append(entropy)
        let base64 = Base64.encode(paddedBytes)

        return "0A" + base64.dropFirst(2)
    }
}

// MARK: - Client Value Store
class ClientValueStore: IClientValueStore {
    private var value: String?

    func store(_ value: String) async throws {
        self.value = value
    }

    func get() async throws -> String {
        guard let value else {
            throw BetterAuthError.nothingToGet
        }

        return value
    }
}

// MARK: - Secp256r1 Verification Key (public key only)
class Secp256r1VerificationKey: IVerificationKey {
    private let publicKeyString: String
    private let _verifier = Secp256r1Verifier()

    init(publicKey: String) {
        self.publicKeyString = publicKey
    }

    func `public`() async throws -> String {
        return publicKeyString
    }

    func verifier() -> any IVerifier {
        return _verifier
    }

    func verify(_ message: String, _ signature: String) async throws {
        try await _verifier.verify(message, signature, publicKeyString)
    }
}

// MARK: - Verification Key Store
class VerificationKeyStore: IVerificationKeyStore {
    private var cache: [String: Secp256r1VerificationKey] = [:]

    func get(identity: String) async throws -> any IVerificationKey {
        // Check cache first
        if let cachedKey = cache[identity] {
            return cachedKey
        }

        // Fetch from server
        let url = URL(string: "http://keys.better-auth.local/keys")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BetterAuthError.invalidData
        }

        let jsonString = String(data: data, encoding: .utf8) ?? "{}"

        // Decode JSON to extract the key for this identity
        guard let jsonData = jsonString.data(using: .utf8),
              let keysMap = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
              let publicKey = keysMap[identity] else {
            throw BetterAuthError.invalidData
        }

        // Create verification key and cache it
        let verificationKey = Secp256r1VerificationKey(publicKey: publicKey)
        cache[identity] = verificationKey

        return verificationKey
    }
}

// MARK: - Timestamper
class Rfc3339Nano: ITimestamper {
    func format(_ when: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: when)
    }

    func parse(_ when: Any) throws -> Date {
        if let date = when as? Date {
            return date
        }
        guard let string = when as? String else {
            throw BetterAuthError.invalidData
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: string) else {
            throw BetterAuthError.invalidData
        }
        return date
    }

    func now() -> Date {
        Date()
    }
}

// MARK: - Placeholder Network
class PlaceholderNetwork: INetwork {
    private let baseURL: String

    init(baseURL: String = "http://auth.better-auth.local") {
        self.baseURL = baseURL
    }

    func sendRequest(_ path: String, _ body: String) async throws -> String {
        var subdomain = "auth"
        var actualPath = path

        // Check if path has a server prefix (e.g., "app-py:/foo/bar")
        if path.contains(":/") {
            let parts = path.components(separatedBy: ":")
            if parts.count == 2 {
                subdomain = parts[0]
                actualPath = parts[1]
            }
        }

        let url = URL(string: "http://\(subdomain).better-auth.local\(actualPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BetterAuthError.invalidData
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Default Paths (using structs from BetterAuth)
func createDefaultPaths() -> IAuthenticationPaths {
    return IAuthenticationPaths(
        account: AccountPaths(
            create: "/account/create",
            recover: "/account/recover",
            delete: "/account/delete"
        ),
        session: SessionPaths(
            request: "/session/request",
            create: "/session/create",
            refresh: "/session/refresh"
        ),
        device: DevicePaths(
            rotate: "/device/rotate",
            link: "/device/link",
            unlink: "/device/unlink"
        ),
        recovery: RecoveryPaths(
            change: "/recovery/change"
        )
    )
}

