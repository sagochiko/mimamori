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

/// A row of `GET /cases`.
public struct Case: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let alertId: String
    public let state: CaseState
    public let assigneeMemberId: String?
    public let notifiedAt: Date
    public let acceptedAt: Date?
    public let resolvedAt: Date?

    public init(id: String, alertId: String, state: CaseState, assigneeMemberId: String?, notifiedAt: Date, acceptedAt: Date?, resolvedAt: Date?) {
        self.id = id
        self.alertId = alertId
        self.state = state
        self.assigneeMemberId = assigneeMemberId
        self.notifiedAt = notifiedAt
        self.acceptedAt = acceptedAt
        self.resolvedAt = resolvedAt
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
