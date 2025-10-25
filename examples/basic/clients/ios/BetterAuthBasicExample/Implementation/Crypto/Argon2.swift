import Foundation
import BLAKE3

class Argon2 {
    static func deriveBytes(passphrase: String, byteCount: Int) async throws -> [UInt8] {
        let saltInputString = "\(passphrase)salt"
        let saltInput = saltInputString.data(using: .utf8)!
        let blake3Hash = BLAKE3.hash(contentsOf: saltInput)
        let saltBytes = Array(Data(blake3Hash))

        let passwordData = passphrase.data(using: .utf8)!
        var output = [UInt8](repeating: 0, count: byteCount)

        let result = passwordData.withUnsafeBytes { passwordPtr in
            saltBytes.withUnsafeBytes { saltPtr in
                output.withUnsafeMutableBytes { outputPtr in
                    argon2id_hash_raw(
                        9,                                          // t_cost (iterations)
                        262144,                                     // m_cost (memory in KiB)
                        1,                                          // parallelism
                        passwordPtr.baseAddress,                    // pwd
                        passwordData.count,                         // pwdlen
                        saltPtr.baseAddress,                        // salt
                        saltBytes.count,                            // saltlen
                        outputPtr.baseAddress,                      // hash
                        byteCount                                   // hashlen
                    )
                }
            }
        }

        guard result == ARGON2_OK.rawValue else {
            throw NSError(domain: "Argon2Error", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Argon2 hash failed with code \(result)"])
        }

        return output
    }
}
