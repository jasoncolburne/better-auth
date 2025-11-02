import Foundation
import BetterAuth
import Security

class HardwareSecp256r1: ISigningKey {
    private var tag: String  // UUID tag for keychain
    private let _verifier = Secp256r1Verifier()

    init(tag: String) {
        self.tag = tag
    }

    // Generate a new key with this tag
    func generate() async {
        #if targetEnvironment(simulator)
        // For simulator, use hardware APIs without Secure Enclave
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]

        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            fatalError("Failed to generate key: \(error!.takeRetainedValue())")
        }
        #else
        // For real devices, try to use Secure Enclave
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
                kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    [],
                    nil
                )!
            ]
        ]

        var error: Unmanaged<CFError>?
        if SecKeyCreateRandomKey(attributes as CFDictionary, &error) == nil {
            // Fallback to non-Secure Enclave if not available
            attributes = [
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeySizeInBits as String: 256,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                ]
            ]

            guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
                fatalError("Failed to generate key: \(error!.takeRetainedValue())")
            }
        }
        #endif
    }

    func sign(_ message: String) async throws -> String {
        // Load key from keychain using the tag
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let privateKey = item as! SecKey? else {
            throw ExampleError.keypairNotGenerated
        }

        // Sign the message
        let messageBytes = message.data(using: .utf8)!
        var error: Unmanaged<CFError>?
        guard let derSignature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            messageBytes as CFData,
            &error
        ) as Data? else {
            throw ExampleError.invalidData
        }

        // Convert DER signature to raw format (r + s)
        // DER format: 0x30 [total-length] 0x02 [r-length] [r-bytes] 0x02 [s-length] [s-bytes]
        guard derSignature.count > 8,
              derSignature[0] == 0x30,
              derSignature[2] == 0x02 else {
            throw ExampleError.invalidData
        }

        let rLength = Int(derSignature[3])
        let rStart = 4
        let sLengthPos = rStart + rLength + 1

        // Validate bounds
        guard sLengthPos < derSignature.count,
              derSignature[sLengthPos - 1] == 0x02 else {
            throw ExampleError.invalidData
        }

        let sLength = Int(derSignature[sLengthPos])
        let sStart = sLengthPos + 1

        guard sStart + sLength <= derSignature.count else {
            throw ExampleError.invalidData
        }

        // Extract r and s, removing any leading zero padding
        var r = Data(derSignature[rStart..<(rStart + rLength)])
        var s = Data(derSignature[sStart..<(sStart + sLength)])

        // Remove leading zero if present (added for DER encoding when high bit is set)
        if r.count == 33 && r.first == 0x00 {
            r = Data(r.dropFirst())
        }
        if s.count == 33 && s.first == 0x00 {
            s = Data(s.dropFirst())
        }

        // Ensure both r and s are exactly 32 bytes by padding if needed
        var rawSignature = Data()
        if r.count < 32 {
            rawSignature.append(Data(repeating: 0, count: 32 - r.count))
        }
        rawSignature.append(r)

        if s.count < 32 {
            rawSignature.append(Data(repeating: 0, count: 32 - s.count))
        }
        rawSignature.append(s)

        // Encode signature in CESR format
        var paddedBytes = Data([0, 0])
        paddedBytes.append(rawSignature)
        let base64 = Base64.encode(paddedBytes)

        return "0I" + base64.dropFirst(2)
    }

    func `public`() async throws -> String {
        // Load key from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let privateKey = item as! SecKey? else {
            throw ExampleError.keypairNotGenerated
        }

        // Get public key
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ExampleError.invalidData
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw ExampleError.invalidData
        }

        // Convert to compressed format
        // The public key data from SecKey is in uncompressed format (65 bytes: 0x04 + x + y)
        // We need compressed format (33 bytes: 0x02/0x03 + x)
        let compressed: Data
        if publicKeyData.count == 65 && publicKeyData[0] == 0x04 {
            let x = publicKeyData[1..<33]
            let y = publicKeyData[33..<65]
            let prefix: UInt8 = (y.last! & 0x01) == 0 ? 0x02 : 0x03
            compressed = Data([prefix]) + x
        } else {
            compressed = publicKeyData
        }

        // Encode in CESR format
        var paddedBytes = Data([0, 0, 0])
        paddedBytes.append(compressed)
        let base64 = Base64.encode(paddedBytes)

        let result = "1AAI" + base64.dropFirst(4)
        return result
    }

    func verifier() -> any IVerifier {
        _verifier
    }

    func verify(_ message: String, _ signature: String) async throws {
        try await _verifier.verify(message, signature, self.public())
    }

    // Delete the key from keychain
    func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag.data(using: .utf8)!
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }

    // Get the tag of this key
    func getTag() -> String {
        return tag
    }
}
