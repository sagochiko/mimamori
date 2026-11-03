import Foundation

// What the family cards and the protected person's screen show for a case ("引き受け" in
// docs/design.md). The screens only lay these out; every rule is here so it can be tested.

/// A button on a family card. One-word verbs; the meaning goes to VoiceOver in the App.
public enum CardAction: String, CaseIterable, Sendable {
  case accept, reply, call, resolve

  public var title: String {
    switch self {
    case .accept: "引き受ける"
    case .reply: "母に返事する"
    case .call: "電話する"
    case .resolve: "解決"
    }
  }
}

/// One case as a family member sees it.
public struct FamilyCard: Equatable, Sendable {
  public let item: Case
  /// "(名前)が対応中" or "解決". Nothing while nobody has accepted.
  public let status: String?
  public let actions: [CardAction]

  /// `me` is this device's member id. Only the assignee can reply and resolve; the others can still call.
  public init(_ item: Case, me: String?) {
    self.item = item
    let name = item.assignee?.displayName ?? "家族"
    switch item.state {
    case .notified:
      status = nil
      actions = [.accept, .call]
    case .accepted where item.assigneeMemberId != nil && item.assigneeMemberId == me:
      status = "\(name)が対応中"
      actions = [.reply, .call, .resolve]
    case .accepted:
      status = "\(name)が対応中"
      actions = [.call]
    case .resolved:
      status = "解決"
      actions = []
    }
  }
}

/// One line on the protected person's screen.
///
/// While nobody has accepted, it says only "家族に伝えました", and after 30 minutes "家族から返事がまだ。
/// 急ぐなら電話して": never "解決" or "対応中", so she does not stop waiting for a reply that is
/// not coming. Once someone accepts, it names them, and their latest reply is shown as "(名前)から".
public struct ProtectedNotice: Equatable, Sendable, Identifiable {
  public struct Reply: Equatable, Sendable {
    public let relayId: String
    /// "(名前)から"
    public let from: String
    public let body: String

    public init(relayId: String, from: String, body: String) {
      self.relayId = relayId
      self.from = from
      self.body = body
    }
  }

  /// The case id.
  public let id: String
  public let status: String?
  /// What was passed to the family ("何を伝えたかを母が見られるようにする" in docs/design.md).
  public let summary: String?
  public let reply: Reply?

  public init(id: String, status: String?, summary: String? = nil, reply: Reply?) {
    self.id = id
    self.status = status
    self.summary = summary
    self.reply = reply
  }

  public static let toldFamily = "家族に伝えました"
  public static let noReplyYet = "家族から返事がまだ。急ぐなら電話して"
  /// Same as the server's watch (server/src/cases.ts, UNANSWERED_AFTER_MS).
  public static let unansweredAfter: TimeInterval = 30 * 60
  /// Open cases older than this leave the screen, so a case the family forgot does not stay forever.
  static let openShownFor: TimeInterval = 3 * 24 * 3600
  /// A reply in a resolved case stays this long.
  static let replyShownFor: TimeInterval = 24 * 3600
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
    let latest = item.relays.max { $0.createdAt < $1.createdAt }
    let reply = latest.map { Reply(relayId: $0.id, from: "\($0.fromName)から", body: $0.body) }
    let summary = item.alert.map(\.summary).flatMap { $0.isEmpty ? nil : $0 }
    switch item.state {
    case .notified:
      guard now.timeIntervalSince(item.notifiedAt) < openShownFor else { return nil }
      let waitedTooLong =
        item.renotifiedAt != nil || now.timeIntervalSince(item.notifiedAt) >= unansweredAfter
      return ProtectedNotice(
        id: item.id, status: waitedTooLong ? noReplyYet : toldFamily, summary: summary, reply: nil)
    case .accepted:
      guard now.timeIntervalSince(item.notifiedAt) < openShownFor || reply != nil else {
        return nil
      }
      let name = item.assignee?.displayName ?? "家族"
      return ProtectedNotice(id: item.id, status: "\(name)が見ています", summary: summary, reply: reply)
    case .resolved:
      guard let latest, let reply, now.timeIntervalSince(latest.createdAt) < replyShownFor else {
        return nil
      }
      return ProtectedNotice(id: item.id, status: nil, summary: summary, reply: reply)
    }
  }
}

/// Which replies were already read aloud. The App keeps it in UserDefaults.
public protocol SpokenStore: Sendable {
  func load() -> Set<String>
  func save(_ ids: Set<String>)
}

public final class InMemorySpokenStore: SpokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var ids: Set<String> = []
  public init() {}
  public func load() -> Set<String> { lock.withLock { ids } }
  public func save(_ ids: Set<String>) { lock.withLock { self.ids = ids } }
}

/// Decides what to read aloud on the protected person's iPhone: each family reply once, oldest
/// first. The App speaks the lines with the normal system voice (AVSpeechSynthesizer); a family
/// member's own voice is not used, so a voice that sounds like family is never a reason to trust.
public struct ReplyAnnouncer: Sendable {
  private let store: any SpokenStore
  /// Ids kept, so the stored set does not grow without end.
  static let remembered = 200

  public init(store: any SpokenStore) {
    self.store = store
  }

  /// The lines to speak now ("(名前)から。(返事)"), marked as spoken.
  public func toSpeak(_ notices: [ProtectedNotice]) -> [String] {
    var spoken = store.load()
    let fresh = notices.compactMap(\.reply).filter { !spoken.contains($0.relayId) }
    guard !fresh.isEmpty else { return [] }
    // Notices come newest first; read in the order they arrived.
    let ordered = Array(fresh.reversed())
    for reply in ordered { spoken.insert(reply.relayId) }
    if spoken.count > Self.remembered {
      let keep = Set(notices.compactMap(\.reply?.relayId))
      spoken = spoken.filter { keep.contains($0) }
    }
    store.save(spoken)
    return ordered.map { "\($0.from)。\($0.body)" }
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
