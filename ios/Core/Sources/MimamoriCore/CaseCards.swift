import Foundation

// What the family cards and the protected person's screen show for a case ("家族への知らせと解決" in
// docs/design.md). The family only learns what she is troubled by, how dangerous it is, and whether
// it was solved: every member sees the same card, and whoever talked with her presses "解決". The
// screens only lay these out; every rule is here so it can be tested.

/// A button on a family card. One-word verbs; the meaning goes to VoiceOver in the App.
public enum CardAction: String, CaseIterable, Sendable {
  case call, resolve

  public var title: String {
    switch self {
    case .call: "電話する"
    case .resolve: "解決"
    }
  }
}

/// One case as a family member sees it. Every member sees the same card.
public struct FamilyCard: Equatable, Sendable {
  public let item: Case
  /// "まだ解決していない", or "(名前)が解決".
  public let status: String
  public let actions: [CardAction]

  public static let notResolved = "まだ解決していない"

  public init(_ item: Case) {
    self.item = item
    switch item.state {
    case .notified:
      status = Self.notResolved
      actions = [.call, .resolve]
    case .resolved:
      status = "\(item.resolvedBy?.displayName ?? "家族")が解決"
      actions = []
    }
  }
}

/// A button of the question that "解決" asks first. One verb each; the meaning goes to VoiceOver.
public enum ResolveChoice: String, CaseIterable, Sendable {
  case resolve, cancel

  public var title: String {
    switch self {
    case .resolve: "解決にする"
    case .cancel: "やめる"
    }
  }
}

/// "解決" asks before it sends (#60): a mistaken press would stop the 30-minute watch, take the case
/// off the protected person's screen, and tell the rest of the family "(名前)が解決". Only
/// "解決にする" sends, once; "やめる", or closing the question, sends nothing.
public struct ResolveConfirmation: Equatable, Sendable {
  /// The case being asked about, while the question is shown.
  public private(set) var asking: Case?

  public init() {}

  /// "解決" was pressed on this case. A resolved case has no "解決" to ask about.
  public mutating func ask(_ item: Case) {
    guard item.state == .notified else { return }
    asking = item
  }

  /// Closes the question. Returns the case to send `POST /cases/{id}/resolve` for, or nil to send nothing.
  public mutating func choose(_ choice: ResolveChoice) -> Case? {
    defer { asking = nil }
    return choice == .resolve ? asking : nil
  }

  /// The question's title: the card's one line, so it is clear which case is being resolved, or
  /// "解決" when the case has none. The question has no sentence of its own.
  public static func title(for item: Case) -> String {
    guard let summary = item.alert?.summary, !summary.isEmpty else { return CardAction.resolve.title }
    return summary
  }
}

/// One line on the protected person's screen.
///
/// While the case is open, it says "家族に伝えました", and after 30 minutes "家族から返事がまだ。急ぐなら
/// 電話して": never "解決" or a family member's name, so she does not stop calling for help when nobody
/// has answered. While no family device took the notice, it says "家族に届いていません。急ぐなら電話して"
/// instead of either, until a retry gets through (#60). A resolved case leaves her screen.
public struct ProtectedNotice: Equatable, Sendable, Identifiable {
  /// The case id.
  public let id: String
  public let status: String
  /// What was passed to the family ("何を伝えたかを母が見られるようにする" in docs/design.md).
  public let summary: String?

  public init(id: String, status: String, summary: String? = nil) {
    self.id = id
    self.status = status
    self.summary = summary
  }

  /// What VoiceOver says for the summary line. "家族に伝えたこと" only when a family device took it.
  public var summaryLabel: String? {
    summary.map { status == Self.notReached ? "相談、\($0)" : "家族に伝えたこと、\($0)" }
  }

  public static let toldFamily = "家族に伝えました"
  public static let noReplyYet = "家族から返事がまだ。急ぐなら電話して"
  /// Same as the server's NOT_REACHED (server/src/cases.ts): no family device took the notice yet.
  public static let notReached = "家族に届いていません。急ぐなら電話して"
  /// Same as the server's watch (server/src/cases.ts, UNANSWERED_AFTER_MS).
  public static let unansweredAfter: TimeInterval = 30 * 60
  /// Open cases older than this leave the screen, so a case the family forgot does not stay forever.
  static let openShownFor: TimeInterval = 3 * 24 * 3600
  static let maxShown = 3

  /// The lines for the screen, newest case first, at most three.
  public static func notices(from cases: [Case], now: Date) -> [ProtectedNotice] {
    cases
      .sorted { $0.notifiedAt > $1.notifiedAt }
      .compactMap { notice(for: $0, now: now) }
      .prefix(maxShown)
      .map { $0 }
  }

  private static func notice(for item: Case, now: Date) -> ProtectedNotice? {
    guard item.state == .notified, now.timeIntervalSince(item.notifiedAt) < openShownFor else {
      return nil
    }
    let summary = item.alert.map(\.summary).flatMap { $0.isEmpty ? nil : $0 }
    let waitedTooLong =
      item.renotifiedAt != nil || now.timeIntervalSince(item.notifiedAt) >= unansweredAfter
    let status = !item.familyWasTold ? notReached : waitedTooLong ? noReplyYet : toldFamily
    return ProtectedNotice(id: item.id, status: status, summary: summary)
  }
}

/// The protected person's number, entered once on a family member's iPhone for "電話する".
/// It stays on that device and is never sent to the server.
public struct PhoneNumber: Equatable, Sendable {
  public let digits: String

  public init?(_ text: String) {
    var kept = ""
    for (i, ch) in text.trimmingCharacters(in: .whitespaces).enumerated() {
      if ch.isASCII, ch.isNumber {
        kept.append(ch)
      } else if ch == "+", i == 0 {
        kept.append(ch)
      } else if " -()".contains(ch) {
        continue
      } else {
        return nil
      }
    }
    let count = kept.filter(\.isNumber).count
    guard (10...15).contains(count) else { return nil }
    digits = kept
  }

  public var url: URL { URL(string: "tel:\(digits)")! }
}
