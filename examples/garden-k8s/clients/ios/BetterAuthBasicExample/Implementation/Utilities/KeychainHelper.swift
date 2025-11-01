import Foundation
import Security

enum KeychainError: Error {
    case unableToStore
    case unableToLoad
    case unableToDelete
    case keyNotFound
    case unableToConvertData
}

class KeychainHelper {
    static let shared = KeychainHelper()

    private init() {}

    // Store a Secure Enclave key reference in the keychain
    func storeKey(_ key: SecKey, withIdentifier identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: identifier.data(using: .utf8)!,
            kSecValueRef as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete any existing key with this identifier
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }

    // Load a key from the keychain
    func loadKey(withIdentifier identifier: String) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: identifier.data(using: .utf8)!,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            throw KeychainError.keyNotFound
        }

        guard let key = item else {
            throw KeychainError.unableToLoad
        }

        return (key as! SecKey)
    }

    // Delete a key from the keychain
    func deleteKey(withIdentifier identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: identifier.data(using: .utf8)!
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }

    // Store a string value in the keychain
    func storeString(_ value: String, withKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unableToConvertData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete any existing value
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToStore
        }
    }

    // Load a string value from the keychain
    func loadString(withKey key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            throw KeychainError.keyNotFound
        }

        guard let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unableToConvertData
        }

        return string
    }

    // Delete a string value from the keychain
    func deleteString(withKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
}
