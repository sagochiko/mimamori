import Foundation

/// The words a one-line reply can be, the same list as the server's (`SMILE_NOTES` in
/// server/src/smiles.ts). No free text goes from one member to another: the author chose set words
/// on 2026-11-05 (docs/design.md, "毎朝の笑顔"). Sent as the raw value. Since 2026-11-07 (#223) the
/// app sends none; it stays because `POST /smiles` in docs/plan.md still takes them.
public enum SmileNote: String, CaseIterable, Sendable, Identifiable {
  case goodMorning = "good-morning"
  case niceSmile = "nice-smile"
  case thanks = "thanks"
  case doingFine = "doing-fine"
  case seeYou = "see-you"

  public var id: String { rawValue }

  public var text: String {
    switch self {
    case .goodMorning: "おはよう"
    case .niceSmile: "いい笑顔"
    case .thanks: "ありがとう"
    case .doingFine: "元気だよ"
    case .seeYou: "またね"
    }
  }
}

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

/// `GET` and `PUT /members/me/settings` (#282): whether this family member gets the two smile
/// notices. Both are on until turned off. Notices of danger, the watch's self-check, and joins have no
/// switch here. The hour her smile is expected by is the family's one value in `SmileBoard`.
public struct MemberSettings: Codable, Hashable, Sendable {
  /// "笑顔が届いたとき": a smile from someone else in the family.
  public var smileNotify: Bool
  /// "笑顔が届かないとき": her smile has not come by the family's hour.
  public var smileMissedNotify: Bool

  public init(smileNotify: Bool = true, smileMissedNotify: Bool = true) {
    self.smileNotify = smileNotify
    self.smileMissedNotify = smileMissedNotify
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

  /// The rows the screens show: smiles with a photo, newest first. A row with only one of the set
  /// words is left out, and a photo's words are not shown: the author dropped the set words from both
  /// screens on 2026-11-07 (#223, docs/design.md, "毎朝の笑顔"). The server still takes and lists them.
  public var photos: [Smile] { smiles.filter(\.hasPhoto) }

  /// The row on her screen: the family's photos only (`role` family), not her own nor those of the
  /// member she was before reinstalling (the server keeps that member, #243), nor those of anyone who
  /// left. The author chose this on 2026-11-07 (docs/design.md, "毎朝の笑顔").
  public var familyPhotos: [Smile] { photos.filter { $0.role == .family } }

  /// The newest photo the protected member took on the calendar day of `now`.
  public func todaysProtectedSmile(now: Date, calendar: Calendar = .current) -> Smile? {
    smiles.first { $0.role == .protected && $0.hasPhoto && calendar.isDate($0.createdAt, inSameDayAs: now) }
  }
}
