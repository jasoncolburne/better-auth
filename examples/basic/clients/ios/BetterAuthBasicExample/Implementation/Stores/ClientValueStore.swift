import Foundation
import BetterAuth

class ClientValueStore: IClientValueStore {
    private let keychainHelper = KeychainHelper.shared
    private let suffix: String

    private var currentValue: String { "better_auth_\(suffix)_value" }

    init(suffix: String) {
        self.suffix = suffix
    }

    func store(_ value: String) async throws {
        try? self.keychainHelper.storeString(value, withKey: currentValue)
    }

    func get() async throws -> String {
        return try self.getSync()
    }

    func getSync() throws -> String {
        if let value = try? self.keychainHelper.loadString(withKey: currentValue) {
            return value
        }

        throw BetterAuthError.callInitializeFirst
    }
}
