/// A 6-digit invite code (`invites.code`). Only ASCII digits count: full-width and other
/// scripts' digits are rejected, because the server compares the code as plain text.
public struct InviteCode: Hashable, Sendable, CustomStringConvertible {
    public static let length = 6

    public let value: String

    public init?(_ raw: String) {
        guard raw.utf8.count == Self.length, raw.utf8.allSatisfy(Self.isASCIIDigit) else { return nil }
        value = raw
    }

    /// Keeps only ASCII digits, up to six, for a text field while the person is typing.
    public static func sanitize(_ typed: String) -> String {
        String(typed.unicodeScalars.filter { $0.isASCII && isASCIIDigit(UInt8($0.value)) }.prefix(length).map(Character.init))
    }

    public var description: String { value }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}

extension InviteCode: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let code = InviteCode(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invite code must be 6 ASCII digits")
        }
        self = code
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
