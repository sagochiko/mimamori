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

/// `cases.state`.
public enum CaseState: String, Codable, Sendable, CaseIterable {
    case notified, accepted, resolved
}

/// Who took a case, with the name the others see ("(名前)が対応中").
public struct CaseMember: Codable, Hashable, Sendable {
    public let memberId: String
    public let displayName: String

    public init(memberId: String, displayName: String) {
        self.memberId = memberId
        self.displayName = displayName
    }
}

/// The alert a case was opened for, as the family card shows it.
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

/// A reply the assignee wrote to the protected person (`relays`). Plain text, read aloud with the
/// normal system voice on the protected person's iPhone.
public struct Relay: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let fromMemberId: String
    public let fromName: String
    public let body: String
    public let createdAt: Date

    public init(id: String, fromMemberId: String, fromName: String, body: String, createdAt: Date) {
        self.id = id
        self.fromMemberId = fromMemberId
        self.fromName = fromName
        self.body = body
        self.createdAt = createdAt
    }
}

/// A row of `GET /cases` (server/src/cases.ts, `CaseView`). Fields added in task 10 may be missing
/// from an older server and then read as empty.
public struct Case: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let alertId: String?
    public let state: CaseState
    public let assigneeMemberId: String?
    public let assignee: CaseMember?
    public let notifiedAt: Date
    public let acceptedAt: Date?
    public let resolvedAt: Date?
    /// Set when the server's 30-minute watch found nobody had accepted.
    public let renotifiedAt: Date?
    public let alert: CaseAlert?
    /// What the AI told the protected person before a family member took over.
    public let aiReply: String?
    public let relays: [Relay]

    public init(
        id: String, alertId: String?, state: CaseState, assigneeMemberId: String?, assignee: CaseMember? = nil,
        notifiedAt: Date, acceptedAt: Date?, resolvedAt: Date?, renotifiedAt: Date? = nil,
        alert: CaseAlert? = nil, aiReply: String? = nil, relays: [Relay] = []
    ) {
        self.id = id
        self.alertId = alertId
        self.state = state
        self.assigneeMemberId = assigneeMemberId
        self.assignee = assignee
        self.notifiedAt = notifiedAt
        self.acceptedAt = acceptedAt
        self.resolvedAt = resolvedAt
        self.renotifiedAt = renotifiedAt
        self.alert = alert
        self.aiReply = aiReply
        self.relays = relays
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        alertId = try c.decodeIfPresent(String.self, forKey: .alertId)
        state = try c.decode(CaseState.self, forKey: .state)
        assigneeMemberId = try c.decodeIfPresent(String.self, forKey: .assigneeMemberId)
        assignee = try c.decodeIfPresent(CaseMember.self, forKey: .assignee)
        notifiedAt = try c.decode(Date.self, forKey: .notifiedAt)
        acceptedAt = try c.decodeIfPresent(Date.self, forKey: .acceptedAt)
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        renotifiedAt = try c.decodeIfPresent(Date.self, forKey: .renotifiedAt)
        alert = try c.decodeIfPresent(CaseAlert.self, forKey: .alert)
        aiReply = try c.decodeIfPresent(String.self, forKey: .aiReply)
        relays = try c.decodeIfPresent([Relay].self, forKey: .relays) ?? []
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
