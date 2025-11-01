import Foundation
import BetterAuth

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
