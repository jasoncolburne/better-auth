import Foundation
import BetterAuth

class FakeResponseMessage: ServerResponse<[String: Any]> {
    var response: FakeResponse {
        let payload = self.payload as! [String: Any]
        let responseDict = payload["response"] as! [String: Any]
        return FakeResponse(
            wasFoo: responseDict["wasFoo"] as! String,
            wasBar: responseDict["wasBar"] as! String,
            serverName: responseDict["serverName"] as! String
        )
    }

    var serverIdentity: String {
        let payload = self.payload as! [String: Any]
        let access = payload["access"] as! [String: Any]
        return access["serverIdentity"] as! String
    }

    static func parse(_ message: String) throws -> FakeResponseMessage {
        try ServerResponse<[String: Any]>.parse(message) { response, serverIdentity, nonce in
            let msg = FakeResponseMessage(response: response, serverIdentity: serverIdentity, nonce: nonce)
            return msg
        } as! FakeResponseMessage
    }
}
