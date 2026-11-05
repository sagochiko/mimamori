import Foundation

/// What the Message Filter extension does with an SMS from an unknown sender. The extension maps it to
/// `ILMessageFilterAction` (ios/MessageFilter); this type stays Foundation-only so `swift test` runs on macOS.
/// There is no "allow": the app never tells the system a message is fine.
public enum SMSFilterVerdict: Equatable, Sendable {
    /// Clearly dangerous by the server's rules: to the junk folder.
    case junk
    /// Delivered as usual. Also the answer for every failure, since a genuine message in the junk folder
    /// (a verification code, a real delivery notice) is the worse mistake.
    case none
}

/// Reads the reply of `POST /sms/{familyToken}` (server/src/sms.ts): `{ "action": "junk" | "none" }`.
public enum SMSFilterReply {
    public static func verdict(statusCode: Int?, data: Data?) -> SMSFilterVerdict {
        guard let statusCode, (200..<300).contains(statusCode), let data,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let action = object["action"] as? String
        else { return .none }
        return action == "junk" ? .junk : .none
    }
}
