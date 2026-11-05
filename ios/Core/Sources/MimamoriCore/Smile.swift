import Foundation

/// A row of `GET /smiles`: a smile, a one-line reply, or both, from anyone in the family.
public struct Smile: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let memberId: String
  public let displayName: String
  /// Nil when the sender has left the family.
  public let role: Role?
  public let score: Double?
  public let note: String?
  public let hasPhoto: Bool
  public let createdAt: Date

  public init(
    id: String, memberId: String, displayName: String, role: Role?, score: Double?, note: String?,
    hasPhoto: Bool, createdAt: Date
  ) {
    self.id = id
    self.memberId = memberId
    self.displayName = displayName
    self.role = role
    self.score = score
    self.note = note
    self.hasPhoto = hasPhoto
    self.createdAt = createdAt
  }
}

/// `GET /smiles`: the family's last week, newest first, and the hour (JST) by which the protected
/// member's smile is expected.
public struct SmileBoard: Codable, Hashable, Sendable {
  public static let defaultDeadlineHour = 9
  /// The hours a family can choose (the server accepts the same range).
  public static let deadlineHours = 5...12

  public var smiles: [Smile]
  public var deadlineHour: Int

  public init(smiles: [Smile] = [], deadlineHour: Int = SmileBoard.defaultDeadlineHour) {
    self.smiles = smiles
    self.deadlineHour = deadlineHour
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    smiles = try container.decode([Smile].self, forKey: .smiles)
    deadlineHour = try container.decodeIfPresent(Int.self, forKey: .deadlineHour) ?? Self.defaultDeadlineHour
  }

  /// The newest photo the protected member took on the calendar day of `now`.
  public func todaysProtectedSmile(now: Date, calendar: Calendar = .current) -> Smile? {
    smiles.first { $0.role == .protected && $0.hasPhoto && calendar.isDate($0.createdAt, inSameDayAs: now) }
  }
}
