import Foundation

enum Base64 {
    static func encode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }

    static func decode(_ base64Str: String) -> Data {
        let normalized = base64Str.replacingOccurrences(of: "_", with: "/").replacingOccurrences(
            of: "-", with: "+"
        )
        return Data(base64Encoded: normalized)!
    }
}
