import Foundation
import BetterAuth

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
