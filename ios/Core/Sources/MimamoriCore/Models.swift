import Foundation

/// `members.role`.
public enum Role: String, Codable, Sendable, CaseIterable {
    /// 見守られる人
    case protected
    /// 家族
    case family
}

/// `Member { id, familyId, role, displayName }` from task 2.
public struct Member: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let familyId: String
    public let role: Role
    public let displayName: String

    public init(id: String, familyId: String, role: Role, displayName: String) {
        self.id = id
        self.familyId = familyId
        self.role = role
        self.displayName = displayName
    }
}

/// How dangerous something is. There are exactly three levels and no "safe":
/// 1 開かないで, 2 家族に確かめるまで待って, 3 心配は少ないけど、お金や暗証番号を聞かれたら止めて.
/// Decoding any other value fails instead of falling back to a milder level.
public enum Level: Int, Codable, Sendable, CaseIterable, Comparable {
    case doNotOpen = 1
    case waitForFamily = 2
    case lowConcern = 3

    /// Lower raw value is more dangerous, so `.doNotOpen` sorts first.
    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// `alerts.source`.
public enum AlertSource: String, Codable, Sendable, CaseIterable {
    case sms, gmail, dns, page, call, consult
}

/// A row of `GET /alerts`.
public struct Alert: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let familyId: String?
    public let source: AlertSource
    public let level: Level
    public let reasons: [String]
    public let summary: String
    public let createdAt: Date

    public init(id: String, familyId: String?, source: AlertSource, level: Level, reasons: [String], summary: String, createdAt: Date) {
        self.id = id
        self.familyId = familyId
        self.source = source
        self.level = level
        self.reasons = reasons
        self.summary = summary
        self.createdAt = createdAt
    }
}

/// `cases.state` as the family and the protected person see it: not resolved yet, or resolved.
/// The server shows a case left in the old "accepted" state as "notified"; an older server may still
/// send "accepted", which is read the same way, never as resolved. Any other value fails decoding.
public enum CaseState: String, Codable, Sendable, CaseIterable {
    case notified, resolved

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "notified", "accepted": self = .notified
        case "resolved": self = .resolved
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "unknown case state: \(raw)"))
        }
    }
}

/// The family member who pressed "解決" ("(名前)が解決").
public struct CaseMember: Codable, Hashable, Sendable {
    public let memberId: String
    public let displayName: String

    public init(memberId: String, displayName: String) {
        self.memberId = memberId
        self.displayName = displayName
    }
}

/// The alert a case was opened for, as the family card shows it. `summary` is one line made by the
/// rules or Claude, never the protected person's words or the received text cut out.
public struct CaseAlert: Codable, Hashable, Sendable {
    public let level: Level
    public let source: AlertSource
    public let summary: String
    public let reasons: [String]

    public init(level: Level, source: AlertSource, summary: String, reasons: [String]) {
        self.level = level
        self.source = source
        self.summary = summary
        self.reasons = reasons
    }
}

/// A row of `GET /cases` (server/src/cases.ts, `CaseView`). Every family member sees the same case;
/// nobody takes it over. Fields an older server does not send are read as empty.
public struct Case: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let alertId: String?
    public let state: CaseState
    public let notifiedAt: Date
    public let resolvedAt: Date?
    public let resolvedBy: CaseMember?
    /// Set when the server's 30-minute watch found the case not resolved.
    public let renotifiedAt: Date?
    public let alert: CaseAlert?
    /// The last answer the AI gave the protected person in this case.
    public let aiReply: String?

    public init(
        id: String, alertId: String?, state: CaseState, notifiedAt: Date, resolvedAt: Date? = nil,
        resolvedBy: CaseMember? = nil, renotifiedAt: Date? = nil, alert: CaseAlert? = nil, aiReply: String? = nil
    ) {
        self.id = id
        self.alertId = alertId
        self.state = state
        self.notifiedAt = notifiedAt
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
        self.renotifiedAt = renotifiedAt
        self.alert = alert
        self.aiReply = aiReply
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        alertId = try c.decodeIfPresent(String.self, forKey: .alertId)
        state = try c.decode(CaseState.self, forKey: .state)
        notifiedAt = try c.decode(Date.self, forKey: .notifiedAt)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        resolvedBy = try c.decodeIfPresent(CaseMember.self, forKey: .resolvedBy)
        renotifiedAt = try c.decodeIfPresent(Date.self, forKey: .renotifiedAt)
        alert = try c.decodeIfPresent(CaseAlert.self, forKey: .alert)
        aiReply = try c.decodeIfPresent(String.self, forKey: .aiReply)
    }
}

/// The answer of `POST /invites`. Valid for 24 hours.
public struct Invite: Codable, Hashable, Sendable {
    public let code: InviteCode
    public let expiresAt: Date

    public init(code: InviteCode, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

/// `members.apns_env`. Debug builds talk to the sandbox, TestFlight and App Store builds to production.
public enum APNsEnvironment: String, Codable, Sendable {
    case sandbox, production
}
