import Foundation
import BetterAuth

public enum VerificationError: Error {
    case expired
}

let HSM_PUBLIC_KEY = "1AAIAjIhd42fcH957TzvXeMbgX4AftiTT7lKmkJ7yHy3dph9"

struct Key: Codable {
    let body: Body
    let signature: String

    struct Body: Codable {
        let payload: Payload
        let hsmIdentity: String

        struct Payload: Codable {
            let purpose: String
            let publicKey: String
            let expiration: String
        }
    }
}

typealias Response = [String: Key]

class VerificationKeyStore: IVerificationKeyStore {
    private var cache: [String: Secp256r1VerificationKey] = [:]
    private var verifier = Secp256r1Verifier()
    private var timestamper = Rfc3339Nano()

    func get(identity: String) async throws -> any IVerificationKey {
        // TODO purge expired identities

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

        // Parse response as dictionary to preserve raw JSON
        guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hsmResponseObj = responseDict[identity] else {
            throw BetterAuthError.invalidData
        }

        // Serialize the HSM response entry to get its raw JSON
        let hsmResponseData = try JSONSerialization.data(withJSONObject: hsmResponseObj)

        // Parse the HSM response to extract body and signature
        guard let hsmResponse = try JSONSerialization.jsonObject(with: hsmResponseData) as? [String: Any],
              let bodyObj = hsmResponse["body"],
              let signature = hsmResponse["signature"] as? String else {
            throw BetterAuthError.invalidData
        }

        // Serialize just the body object to get the exact JSON bytes that were signed
        let bodyData = try JSONSerialization.data(withJSONObject: bodyObj)
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw BetterAuthError.invalidData
        }

        // Verify the signature using the raw body JSON
        try await verifier.verify(bodyString, signature, HSM_PUBLIC_KEY)

        // Now decode the body to validate its contents
        let decodedBody = try JSONDecoder().decode(Key.Body.self, from: bodyData)

        if (decodedBody.hsmIdentity != HSM_PUBLIC_KEY) {
            throw BetterAuthError.invalidData
        }

        if (decodedBody.payload.purpose != "response") {
            throw BetterAuthError.invalidData
        }

        let expirationTimestamp = try timestamper.parse(decodedBody.payload.expiration)
        if (timestamper.now() > expirationTimestamp) {
            throw VerificationError.expired
        }

        // Create verification key and cache it
        let verificationKey = Secp256r1VerificationKey(publicKey: decodedBody.payload.publicKey)
        cache[identity] = verificationKey
        
        // TODO cache expiration
        return verificationKey
    }
}
