import Foundation
import BetterAuth

class Rfc3339: ITimestamper {
    func format(_ when: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: when)
    }

    func parse(_ when: Any) throws -> Date {
        if let date = when as? Date {
            return date
        }
        guard let string = when as? String else {
            throw ExampleError.invalidData
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: string) else {
            throw ExampleError.invalidData
        }
        return date
    }

    func now() -> Date {
        Date()
    }
}
