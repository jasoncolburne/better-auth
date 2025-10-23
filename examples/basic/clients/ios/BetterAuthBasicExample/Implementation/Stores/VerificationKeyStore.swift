import Foundation
import BetterAuth

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
