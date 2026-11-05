import Foundation

// "さっきの電話、大丈夫だった？" after a long call ("検知" and "アプリからの声かけ" in docs/design.md).
//
// Only the rules live here. On the author's iPhone 16 (iOS 27.2) CXCallObserver reported the end of a
// call only while the app was in front, not after going home or being swiped away (#25, 2026年11月5日).
// So the app passes what it sees while in front (`CallTracker` turns CXCallObserver's changes into an
// `EndedCall`), and the daily prompt (`DailyCheckIn`) covers the calls it never sees (#99).

/// A call that has ended. The number is never known or kept.
public struct EndedCall: Equatable, Sendable {
  /// Anything that names this one call (CXCall's UUID, or an id the trigger makes up).
  public let id: String
  public let duration: TimeInterval
  public let endedAt: Date

  public init(id: String, duration: TimeInterval, endedAt: Date) {
    self.id = id
    self.duration = duration
    self.endedAt = endedAt
  }
}

/// What to do right after a call ended.
public enum FollowUpAction: Equatable, Sendable {
  /// Short call, or this call was already asked about.
  case nothing
  /// A local notification now, and the prompt on her screen.
  case notifyNow
  /// Night: no notification; the prompt waits on her screen for the next time she opens the app.
  case askOnNextOpen
}

/// What is remembered between launches.
public struct CallFollowUpState: Codable, Equatable, Sendable {
  /// Calls already asked about (or decided on), oldest first.
  public var handled: [String] = []
  /// The call whose prompt is still waiting for an answer.
  public var pendingCallId: String?
  public var pendingEndedAt: Date?
  /// When a call was last asked about (notified, or left on her screen for the night). That day's
  /// daily prompt is skipped. Optional so that state saved before #99 still decodes.
  public var lastAskedAt: Date?

  public init() {}
}

public protocol CallFollowUpStore: Sendable {
  func load() -> CallFollowUpState
  func save(_ state: CallFollowUpState)
}

public final class InMemoryCallFollowUpStore: CallFollowUpStore, @unchecked Sendable {
  private let lock = NSLock()
  private var state = CallFollowUpState()
  public init() {}
  public func load() -> CallFollowUpState { lock.withLock { state } }
  public func save(_ state: CallFollowUpState) { lock.withLock { self.state = state } }
}

public final class CallFollowUp: @unchecked Sendable {
  public static let prompt = "さっきの電話、大丈夫だった？"
  /// Calls shorter than this are not asked about. Release builds always use this; a Debug launch
  /// argument can pass a shorter one to the initializer, to film the demo with a short call.
  public static let minimumDuration: TimeInterval = 3 * 60
  /// No notification from 22:00 up to 7:00, device time.
  static let quietFrom = 22
  static let quietUntil = 7
  /// After this, "さっきの電話" no longer makes sense, so the prompt is dropped.
  public static let promptLifetime: TimeInterval = 12 * 3600
  /// Call ids kept, so the stored list does not grow without end.
  public static let remembered = 50

  private let store: any CallFollowUpStore
  private let calendar: Calendar
  private let minimum: TimeInterval
  private let lock = NSLock()

  public init(
    store: any CallFollowUpStore, calendar: Calendar = .current,
    minimumDuration: TimeInterval = CallFollowUp.minimumDuration
  ) {
    self.store = store
    self.calendar = calendar
    self.minimum = minimumDuration
  }

  /// A call ended. Asks at most once per call, and only after a call of 3 minutes or more (or the
  /// shorter minimum a Debug build was launched with).
  public func callEnded(_ call: EndedCall) -> FollowUpAction {
    lock.withLock {
      var state = store.load()
      guard call.duration >= minimum, !state.handled.contains(call.id) else {
        return .nothing
      }
      state.handled.append(call.id)
      if state.handled.count > Self.remembered {
        state.handled.removeFirst(state.handled.count - Self.remembered)
      }
      state.pendingCallId = call.id
      state.pendingEndedAt = call.endedAt
      state.lastAskedAt = call.endedAt
      store.save(state)
      return isQuiet(call.endedAt) ? .askOnNextOpen : .notifyNow
    }
  }

  /// The prompt for her screen while a call is waiting for an answer, otherwise nil.
  public func promptToShow(at now: Date) -> String? {
    lock.withLock {
      var state = store.load()
      guard let endedAt = state.pendingEndedAt else { return nil }
      guard now.timeIntervalSince(endedAt) < Self.promptLifetime else {
        state.pendingCallId = nil
        state.pendingEndedAt = nil
        store.save(state)
        return nil
      }
      return Self.prompt
    }
  }

  /// When to post the daily prompt: `DailyCheckIn.schedule`, skipping the day a call was asked about.
  public func dailyCheckIns(_ settings: DailyCheckInSettings, now: Date) -> [DateComponents] {
    let asked = lock.withLock { store.load().lastAskedAt }
    return DailyCheckIn.schedule(settings, now: now, lastCallFollowUpAt: asked, calendar: calendar)
  }

  /// "大丈夫": nothing else happens. No consultation, nothing to the family.
  public func answeredFine() {
    clearPending()
  }

  /// She started talking to the microphone; the prompt has done its job.
  public func consultStarted() {
    clearPending()
  }

  private func clearPending() {
    lock.withLock {
      var state = store.load()
      state.pendingCallId = nil
      state.pendingEndedAt = nil
      store.save(state)
    }
  }

  private func isQuiet(_ date: Date) -> Bool {
    Self.isQuiet(hour: calendar.component(.hour, from: date))
  }

  /// 22:00 up to 7:00. The one definition for both prompts.
  static func isQuiet(hour: Int) -> Bool {
    hour >= quietFrom || hour < quietUntil
  }
}
