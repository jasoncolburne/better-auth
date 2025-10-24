import Foundation

func getEntropy(_ length: Int) async -> Data {
    var bytes = [UInt8](repeating: 0, count: length)
    let result = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    guard result == errSecSuccess else {
        fatalError("Failed to generate random bytes")
    }
    return Data(bytes)
}
