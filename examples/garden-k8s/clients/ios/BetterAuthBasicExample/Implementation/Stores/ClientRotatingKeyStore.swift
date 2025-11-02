import Foundation
import BetterAuth

class ClientRotatingKeyStore: IClientRotatingKeyStore {
    private let hasher = Hasher()
    private let keychainHelper = KeychainHelper.shared
    private let prefix: String

    // Keychain keys for storing identity -> tag mappings and current/next/future identities
    private var currentIdentityKey: String { "better_auth_\(prefix)_current_identity" }
    private var nextIdentityKey: String { "better_auth_\(prefix)_next_identity" }
    private var futureIdentityKey: String { "better_auth_\(prefix)_future_identity" }

    init(prefix: String) {
        self.prefix = prefix
    }

    // Get identity -> tag mapping key
    private func identityToTagKey(_ identity: String) -> String {
        return "better_auth_\(prefix)_identity_tag_\(identity)"
    }

    func initialize(_ extraData: String?) async throws -> (String, String, String) {
        // Generate two hardware-backed keys
        let currentTag = UUID().uuidString
        let nextTag = UUID().uuidString

        let current = HardwareSecp256r1(tag: currentTag)
        let next = HardwareSecp256r1(tag: nextTag)

        await current.generate()
        await next.generate()

        let suffix = extraData ?? ""

        let publicKey = try await current.public()
        let nextPublicKey = try await next.public()
        let rotationHash = try await hasher.sum(nextPublicKey)
        let identity = try await hasher.sum(publicKey + rotationHash + suffix)

        // Store identity -> tag mappings
        try keychainHelper.storeString(currentTag, withKey: identityToTagKey(publicKey))
        try keychainHelper.storeString(nextTag, withKey: identityToTagKey(nextPublicKey))

        // Store current and next identities
        try keychainHelper.storeString(publicKey, withKey: currentIdentityKey)
        try keychainHelper.storeString(nextPublicKey, withKey: nextIdentityKey)

        return (identity, publicKey, rotationHash)
    }

    func next() async throws -> (any ISigningKey, String) {
        // Load next identity from keychain
        guard let nextIdentity = try? keychainHelper.loadString(withKey: nextIdentityKey) else {
            throw ExampleError.callInitializeFirst
        }

        // Load the tag for next identity
        guard let nextTag = try? keychainHelper.loadString(withKey: identityToTagKey(nextIdentity)) else {
            throw ExampleError.callInitializeFirst
        }

        let nextKey = HardwareSecp256r1(tag: nextTag)

        // Check if future key exists
        let futureIdentity: String
        if let existingFutureIdentity = try? keychainHelper.loadString(withKey: futureIdentityKey) {
            futureIdentity = existingFutureIdentity
        } else {
            // Generate a new future key
            let futureTag = UUID().uuidString
            let futureKey = HardwareSecp256r1(tag: futureTag)
            await futureKey.generate()

            let futurePublicKey = try await futureKey.public()

            // Store future identity and mapping
            try keychainHelper.storeString(futurePublicKey, withKey: futureIdentityKey)
            try keychainHelper.storeString(futureTag, withKey: identityToTagKey(futurePublicKey))

            futureIdentity = futurePublicKey
        }

        let rotationHash = try await hasher.sum(futureIdentity)

        return (nextKey, rotationHash)
    }

    func rotate() async throws {
        guard let nextIdentity = try? keychainHelper.loadString(withKey: nextIdentityKey) else {
            throw ExampleError.callInitializeFirst
        }

        guard let futureIdentity = try? keychainHelper.loadString(withKey: futureIdentityKey) else {
            throw ExampleError.callNextFirst
        }

        // Get current identity to delete its key
        if let currentIdentity = try? keychainHelper.loadString(withKey: currentIdentityKey),
           let currentTag = try? keychainHelper.loadString(withKey: identityToTagKey(currentIdentity)) {
            // Delete the current key from keychain
            let currentKey = HardwareSecp256r1(tag: currentTag)
            try? currentKey.deleteKey()

            // Delete the identity -> tag mapping
            try? keychainHelper.deleteString(withKey: identityToTagKey(currentIdentity))
        }

        // Rotate: current <- next, next <- future, future <- nil
        try keychainHelper.storeString(nextIdentity, withKey: currentIdentityKey)
        try keychainHelper.storeString(futureIdentity, withKey: nextIdentityKey)
        try keychainHelper.deleteString(withKey: futureIdentityKey)
    }

    func signer() async throws -> any ISigningKey {
        guard let currentIdentity = try? keychainHelper.loadString(withKey: currentIdentityKey) else {
            throw ExampleError.callInitializeFirst
        }

        guard let currentTag = try? keychainHelper.loadString(withKey: identityToTagKey(currentIdentity)) else {
            throw ExampleError.callInitializeFirst
        }

        return HardwareSecp256r1(tag: currentTag)
    }

    func isInitialized() -> Bool {
        return (try? keychainHelper.loadString(withKey: currentIdentityKey)) != nil
    }

    func reset() {
        // Delete all identities and their keys
        if let currentIdentity = try? keychainHelper.loadString(withKey: currentIdentityKey),
           let currentTag = try? keychainHelper.loadString(withKey: identityToTagKey(currentIdentity)) {
            let currentKey = HardwareSecp256r1(tag: currentTag)
            try? currentKey.deleteKey()
            try? keychainHelper.deleteString(withKey: identityToTagKey(currentIdentity))
        }

        if let nextIdentity = try? keychainHelper.loadString(withKey: nextIdentityKey),
           let nextTag = try? keychainHelper.loadString(withKey: identityToTagKey(nextIdentity)) {
            let nextKey = HardwareSecp256r1(tag: nextTag)
            try? nextKey.deleteKey()
            try? keychainHelper.deleteString(withKey: identityToTagKey(nextIdentity))
        }

        if let futureIdentity = try? keychainHelper.loadString(withKey: futureIdentityKey),
           let futureTag = try? keychainHelper.loadString(withKey: identityToTagKey(futureIdentity)) {
            let futureKey = HardwareSecp256r1(tag: futureTag)
            try? futureKey.deleteKey()
            try? keychainHelper.deleteString(withKey: identityToTagKey(futureIdentity))
        }

        // Delete position markers
        try? keychainHelper.deleteString(withKey: currentIdentityKey)
        try? keychainHelper.deleteString(withKey: nextIdentityKey)
        try? keychainHelper.deleteString(withKey: futureIdentityKey)
    }
}
