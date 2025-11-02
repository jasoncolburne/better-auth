import Foundation
import BetterAuth
import Crypto

class Secp256r1Verifier: IVerifier {
    var signatureLength: Int { 88 }

    func verify(_ message: String, _ signature: String, _ publicKey: String) async throws {
        let publicKeyBytes = Base64.decode(publicKey).dropFirst(3)
        let signatureBytes = Base64.decode(signature).dropFirst(2)
        let messageBytes = message.data(using: .utf8)!

        let key = try P256.Signing.PublicKey(compressedRepresentation: publicKeyBytes)
        let sig = try P256.Signing.ECDSASignature(rawRepresentation: signatureBytes)

        guard key.isValidSignature(sig, for: messageBytes) else {
            throw ExampleError.invalidData
        }
    }
}
