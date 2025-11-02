import Foundation
import BetterAuth

class Network: INetwork {
    private let baseURL: String

    init(baseURL: String = "http://auth.better-auth.local") {
        self.baseURL = baseURL
    }

    func sendRequest(_ path: String, _ body: String) async throws -> String {
        var subdomain = "auth"
        var actualPath = path

        // Check if path has a server prefix (e.g., "app-py:/foo/bar")
        if path.contains(":/") {
            let parts = path.components(separatedBy: ":")
            if parts.count == 2 {
                subdomain = parts[0]
                actualPath = parts[1]
            }
        }

        let url = URL(string: "http://\(subdomain).better-auth.local\(actualPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExampleError.invalidData
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}
