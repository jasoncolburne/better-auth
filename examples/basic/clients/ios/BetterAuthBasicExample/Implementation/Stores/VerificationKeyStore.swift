import Foundation
import BetterAuth

public enum VerificationError: Error {
    case expiredKey
}

let twelveHours: TimeInterval = 12 * 3600

func extractJSONValues(from jsonString: String, forKey key: String) throws -> [String] {
    var values: [String] = []
    var searchRange = jsonString.startIndex..<jsonString.endIndex

    while let keyRange = jsonString.range(of: "\"\(key)\"", options: [], range: searchRange) {
        // Find the colon after the key
        var currentIndex = keyRange.upperBound
        while currentIndex < jsonString.endIndex && (jsonString[currentIndex].isWhitespace || jsonString[currentIndex] == ":") {
            currentIndex = jsonString.index(after: currentIndex)
        }

        // Now we're at the start of the value (should be '{')
        guard currentIndex < jsonString.endIndex && jsonString[currentIndex] == "{" else {
            throw BetterAuthError.invalidData
        }

        // Extract the complete JSON object by counting braces
        var braceCount = 0
        var inString = false
        var escaped = false
        let startIndex = currentIndex

        while currentIndex < jsonString.endIndex {
            let char = jsonString[currentIndex]

            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        // Found the end of the object
                        let endIndex = jsonString.index(after: currentIndex)
                        let substring = String(jsonString[startIndex..<endIndex])
                        values.append(substring)
                        searchRange = endIndex..<jsonString.endIndex
                        break
                    }
                }
            }

            currentIndex = jsonString.index(after: currentIndex)
        }
    }

    return values
}

struct SignedEntry: Codable {
    let payload: LogEntry
    let signature: String

    struct LogEntry: Codable {
        let id: String
        let prefix: String
        let previous: String?
        let sequenceNumber: Int
        let createdAt: Date
        let purpose: String
        let publicKey: String
        let rotationHash: String
    }
}

class KeyVerifier {
    private let verifier = Secp256r1Verifier()
    private let hasher = Hasher()
    private var cache: [String: SignedEntry] = [:]

    func verify(_ body: String, _ signature: String, _ hsmIdentity: String, _ generationId: String) async throws {
        var cachedEntry = self.cache[generationId]

        if cachedEntry == nil {
            // Fetch from server
            let url = URL(string: "http://keys.better-auth.local/hsm/keys")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode) else {
                throw BetterAuthError.invalidData
            }

            guard let hsmRecords = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                throw BetterAuthError.invalidData
            }

            // Extract raw payload JSON strings directly from the original response
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw BetterAuthError.invalidData
            }

            let payloadStrings = try extractJSONValues(from: jsonString, forKey: "payload")

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decodedEntries = try decoder.decode([SignedEntry].self, from: data)

            var lastId = ""
            var lastRotationHash = ""

            var prefixedEntries: [SignedEntry] = []

            var i = 0
            var payloadIndex = 0
            for entry in decodedEntries {
                let payload = entry.payload
                let payloadString = payloadStrings[payloadIndex]
                payloadIndex += 1

                if payload.prefix != HSM_IDENTITY {
                    continue
                }

                if payload.sequenceNumber != i {
                    throw BetterAuthError.invalidData
                }

                if payload.sequenceNumber == 0 {
                    try await self.verifyPrefixAndData(payloadString, payload)
                } else {
                    if lastId != payload.previous {
                        throw BetterAuthError.invalidData
                    }

                    let hash = try await self.hasher.sum(payload.publicKey)

                    if lastRotationHash != hash {
                        throw BetterAuthError.invalidData
                    }

                    try await self.verifyAddressAndData(payloadString, payload)
                }

                try await self.verifier.verify(payloadString, entry.signature, payload.publicKey)

                prefixedEntries.append(entry)

                lastId = payload.id
                lastRotationHash = payload.rotationHash

                i += 1
            }

            for entry in prefixedEntries.reversed() {
                let payload = entry.payload
                self.cache[payload.id] = entry
                if payload.createdAt + twelveHours < Date() {
                    break
                }
            }

            cachedEntry = self.cache[generationId]
        }

        guard let entry = cachedEntry else {
            throw BetterAuthError.invalidData
        }

        if entry.payload.prefix != hsmIdentity {
            throw BetterAuthError.invalidData
        }

        if entry.payload.purpose != "key-authorization" {
            throw BetterAuthError.invalidData
        }

        try await self.verifier.verify(body, signature, entry.payload.publicKey)
    }

    func verifyPrefixAndData(_ payloadString: String, _ payload: SignedEntry.LogEntry) async throws {
        if payload.id != payload.prefix {
            throw BetterAuthError.invalidData
        }

        try await verifyAddressAndData(payloadString, payload)
    }

    func verifyAddressAndData(_ payloadString: String, _ payload: SignedEntry.LogEntry) async throws {
        let modifiedPayload = payloadString.replacingOccurrences(of: payload.id, with: "############################################")

        let hash = try await self.hasher.sum(modifiedPayload)

        if hash != payload.id {
            throw BetterAuthError.invalidData
        }
    }
}

struct Key: Codable {
    let body: Body
    let signature: String

    struct Body: Codable {
        let payload: Payload
        let hsm: HSM

        struct Payload: Codable {
            let purpose: String
            let publicKey: String
            let expiration: String
        }

        struct HSM: Codable {
            let identity: String
            let generationId: String
        }
    }
}

typealias Response = [String: Key]

class VerificationKeyStore: IVerificationKeyStore {
    private var cache: [String: (Secp256r1VerificationKey, Date)] = [:]
    private var verifier = KeyVerifier()
    private var timestamper = Rfc3339Nano()

    func get(identity: String) async throws -> any IVerificationKey {
        // Check cache first
        if let (cachedKey, expiration) = cache[identity] {
            if (timestamper.now() > expiration) {
                cache.removeValue(forKey: identity)
                throw VerificationError.expiredKey
            }

            return cachedKey
        }

        // Fetch from server
        let url = URL(string: "http://keys.better-auth.local/keys/\(identity)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BetterAuthError.invalidData
        }

        // Extract the raw "body" JSON substring to preserve exact bytes that were signed
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw BetterAuthError.invalidData
        }

        let bodyStrings = try extractJSONValues(from: jsonString, forKey: "body")
        guard let bodyString = bodyStrings.first else {
            throw BetterAuthError.invalidData
        }

        // Parse the response to get the signature
        guard let hsmResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signature = hsmResponse["signature"] as? String else {
            throw BetterAuthError.invalidData
        }

        // Now decode the body to validate its contents
        guard let bodyData = bodyString.data(using: .utf8) else {
            throw BetterAuthError.invalidData
        }
        let decodedBody = try JSONDecoder().decode(Key.Body.self, from: bodyData)

        // Verify the signature using the raw body JSON
        try await verifier.verify(
            bodyString,
            signature,
            decodedBody.hsm.identity,
            decodedBody.hsm.generationId
        )

        if (decodedBody.payload.purpose != "response") {
            throw BetterAuthError.invalidData
        }

        let expirationTimestamp = try timestamper.parse(decodedBody.payload.expiration)

        if (timestamper.now() > expirationTimestamp) {
            throw VerificationError.expiredKey
        }

        // Create verification key and cache it
        let verificationKey = Secp256r1VerificationKey(publicKey: decodedBody.payload.publicKey)
        cache[identity] = (verificationKey, expirationTimestamp)

        return verificationKey
    }
}
