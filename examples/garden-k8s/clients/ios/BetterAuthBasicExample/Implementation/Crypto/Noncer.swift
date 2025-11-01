import Foundation
import BetterAuth

class Noncer: INoncer {
    func generate128() async throws -> String {
        let entropy = await getEntropy(16)

        var paddedBytes = Data([0, 0])
        paddedBytes.append(entropy)
        let base64 = Base64.encode(paddedBytes)

        return "0A" + base64.dropFirst(2)
    }
}
