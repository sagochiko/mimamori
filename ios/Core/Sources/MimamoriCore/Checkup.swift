import Foundation

// "アプリからの声かけ" in docs/design.md (task 17, #19). Like the prompt after a call, the app notices
// on its own and offers to do it together. Only the rules live here; the App reads the free space and
// posts the notification.
//
// Free space comes from an API Apple lists as needing a reason (NSPrivacyAccessedAPICategoryDiskSpace).
// The app declares 85F4.1, "display disk space information to the person using the device", so the
// prompt shows the amount, and "Information accessed for this reason, or any derived information, may
// not be sent off-device". So the amount and whether it is low stay here: they are not kept in the
// state, not put in the guide message (which joins her conversation sent to POST /consult), and not
// in the heartbeat.

/// One kind of check. Only free space for now; the update, calendar, subscription, and iCloud checks
/// come later (task 17, the "周りの機能").
public enum CheckupKind: String, Codable, Sendable, CaseIterable {
  case storage
}

/// What to do after a check.
public enum CheckupAction: Equatable, Sendable {
  case nothing
  /// A local notification with this text now, and the prompt on her screen.
  case notify(String)
}

/// What is remembered between launches, per kind. No amounts.
public struct CheckupState: Codable, Equatable, Sendable {
  /// When she was last asked (the notification went out). One per calendar day.
  public var askedAt: [CheckupKind: Date] = [:]
  /// A prompt waiting on her screen.
  public var pending: Set<CheckupKind> = []
  /// "あとで": nothing until then.
  public var snoozedUntil: [CheckupKind: Date] = [:]

  public init() {}
}

public protocol CheckupStore: Sendable {
  func load() -> CheckupState
  func save(_ state: CheckupState)
  func clear()
}

public final class InMemoryCheckupStore: CheckupStore, @unchecked Sendable {
  private let lock = NSLock()
  private var state = CheckupState()
  public init() {}
  public func load() -> CheckupState { lock.withLock { state } }
  public func save(_ state: CheckupState) { lock.withLock { self.state = state } }
  public func clear() { lock.withLock { state = CheckupState() } }
}

public final class CheckupPolicy: @unchecked Sendable {
  /// Below this, she is asked. Apple's own "almost full" warning comes much later; 2 GB leaves room
  /// for a few days of photos and an app update. A guess, not measured on her iPhone.
  public static let lowStorageBytes: Int64 = 2_000_000_000
  /// "あとで" keeps every prompt of that kind away this long.
  public static let snooze: TimeInterval = 24 * 3600

  /// Her screen's first line after she opens the prompt: where to go, and that no cleaner app is
  /// needed (docs/design.md). No amount and no digit, since it joins the conversation sent to the
  /// server. The menu names are Apple's: 「設定」「一般」「iPhoneストレージ」
  /// (support.apple.com/ja-jp/108429, read on 2026年11月7日).
  public static let storageGuide =
    "一緒に空けよう。設定を開いて、一般、iPhoneストレージの順に押してね。おすすめと、大きいアプリの一覧が出るよ。広告の掃除アプリは入れなくていいよ。迷ったら、その画面のスクショをみまもりに共有してね"

  /// The prompt, with the amount left in GB (as the Settings app counts, 1 GB = 10^9 bytes).
  public static func storagePrompt(availableBytes: Int64) -> String {
    let tenths = max(0, availableBytes) / 100_000_000
    return "iPhoneの空きが残り\(tenths / 10).\(tenths % 10)GB。一緒に空けよう"
  }

  private let store: any CheckupStore
  private let calendar: Calendar
  private let lock = NSLock()

  public init(store: any CheckupStore, calendar: Calendar = .current) {
    self.store = store
    self.calendar = calendar
  }

  /// Free space was read (nil when it could not be). Asks at most once a calendar day, never from
  /// 22:00 up to 7:00 (a night check does not use the day's one), and not while "あとで" holds.
  public func storageChecked(availableBytes: Int64?, at now: Date) -> CheckupAction {
    guard let availableBytes else { return .nothing }
    return lock.withLock {
      var state = store.load()
      guard availableBytes < Self.lowStorageBytes else {
        if state.pending.remove(.storage) != nil { store.save(state) }
        return .nothing
      }
      guard isOpen(.storage, state, at: now) else { return .nothing }
      if let asked = state.askedAt[.storage], calendar.isDate(asked, inSameDayAs: now) {
        return .nothing
      }
      state.askedAt[.storage] = now
      state.pending.insert(.storage)
      store.save(state)
      return .notify(Self.storagePrompt(availableBytes: availableBytes))
    }
  }

  /// The prompt for her screen, from a fresh reading, or nil.
  public func storagePromptToShow(availableBytes: Int64?, at now: Date) -> String? {
    guard let availableBytes, availableBytes < Self.lowStorageBytes else { return nil }
    return lock.withLock {
      let state = store.load()
      guard state.pending.contains(.storage), isOpen(.storage, state, at: now) else { return nil }
      return Self.storagePrompt(availableBytes: availableBytes)
    }
  }

  /// "あとで".
  public func later(_ kind: CheckupKind = .storage, at now: Date) {
    lock.withLock {
      var state = store.load()
      state.pending.remove(kind)
      state.snoozedUntil[kind] = now.addingTimeInterval(Self.snooze)
      store.save(state)
    }
  }

  /// She opened the prompt (on her screen, or by tapping the notification): the prompt closes and
  /// the guide is the first answer in her chat.
  public func startStorageGuide() -> String {
    lock.withLock {
      var state = store.load()
      state.pending.remove(.storage)
      store.save(state)
    }
    return Self.storageGuide
  }

  /// This iPhone is no longer in a family: what was asked goes with the key.
  public func forget() {
    lock.withLock { store.clear() }
  }

  private func isOpen(_ kind: CheckupKind, _ state: CheckupState, at now: Date) -> Bool {
    if CallFollowUp.isQuiet(hour: calendar.component(.hour, from: now)) { return false }
    if let until = state.snoozedUntil[kind], now < until { return false }
    return true
  }
}

// MARK: Heartbeat

/// `POST /heartbeat` (docs/plan.md): whether notifications and background refresh are on. Nothing
/// else, free space least of all.
public struct HeartbeatReport: Codable, Equatable, Sendable {
  public let notificationsOn: Bool
  public let backgroundRefreshOn: Bool

  public init(notificationsOn: Bool, backgroundRefreshOn: Bool) {
    self.notificationsOn = notificationsOn
    self.backgroundRefreshOn = backgroundRefreshOn
  }

  enum CodingKeys: String, CodingKey {
    case notificationsOn = "notifications"
    case backgroundRefreshOn = "backgroundRefresh"
  }
}

/// Keeps the heartbeat to a few a day: the server only needs one within 48 hours, and it runs each
/// time the app comes to the front. A change of setting goes at once, so the family hears soon.
public struct HeartbeatGate: Codable, Equatable, Sendable {
  public static let interval: TimeInterval = 6 * 3600

  public private(set) var lastSentAt: Date?
  public private(set) var lastReport: HeartbeatReport?

  public init() {}

  public func shouldSend(_ report: HeartbeatReport, at now: Date) -> Bool {
    guard let lastSentAt, lastReport == report else { return true }
    return now.timeIntervalSince(lastSentAt) >= Self.interval || now < lastSentAt
  }

  public mutating func sent(_ report: HeartbeatReport, at now: Date) {
    lastSentAt = now
    lastReport = report
  }
}
