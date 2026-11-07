import Foundation

// "知らない人や勧誘の電話で困ったら教えてね" after a long call, at most once a day ("検知" and
// "アプリからの声かけ" in docs/design.md). Not a question: on 2026年11月7日 the author found a question
// after every call too much for her (#123).
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
  /// Short call, this call was already asked about, or a call was already asked about that day.
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
  /// The waiting prompt was left for the night (no notification) and has not been on her screen
  /// yet. If it runs out unseen, it does not count as that day's one (#123, review 1 of PR #238).
  /// Optional so that state saved before still decodes.
  public var pendingUnseen: Bool?
  /// `lastAskedAt` before the unseen prompt set it, put back when that prompt runs out unseen.
  public var askedBeforeUnseen: Date?

  public init() {}
}

public protocol CallFollowUpStore: Sendable {
  func load() -> CallFollowUpState
  func save(_ state: CallFollowUpState)
  /// Deletes what is kept. Nothing kept is not an error.
  func clear()
}

public final class InMemoryCallFollowUpStore: CallFollowUpStore, @unchecked Sendable {
  private let lock = NSLock()
  private var state = CallFollowUpState()
  public init() {}
  public func load() -> CallFollowUpState { lock.withLock { state } }
  public func save(_ state: CallFollowUpState) { lock.withLock { self.state = state } }
  public func clear() { lock.withLock { state = CallFollowUpState() } }
}

public final class CallFollowUp: @unchecked Sendable {
  public static let prompt = "知らない人や勧誘の電話で困ったら教えてね"
  /// Calls shorter than this are not asked about. Release builds always use this; a Debug launch
  /// argument can pass a shorter one to the initializer, to film the demo with a short call.
  public static let minimumDuration: TimeInterval = 3 * 60
  /// No notification from 22:00 up to 7:00, device time.
  static let quietFrom = 22
  static let quietUntil = 7
  /// After this the prompt is too far from the call to mean anything, so it is dropped.
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

  /// A call ended. Asks at most once per call and once a day, and only after a call of 3 minutes or
  /// more (or the shorter minimum a Debug build was launched with).
  ///
  /// The day is the calendar day of the device (`calendar`) the call ended on, compared with the day
  /// of `lastAskedAt`. A prompt left on her screen for the night counts as that night's day, so a call
  /// at 0:30 and another at 10:00 get one prompt. But a night prompt that runs out after 12 hours
  /// without ever being on her screen is not counted: a missed scam call weighs more than a second
  /// prompt. A skipped call changes nothing that is kept.
  public func callEnded(_ call: EndedCall) -> FollowUpAction {
    lock.withLock {
      var state = store.load()
      if dropExpired(&state, now: call.endedAt) { store.save(state) }
      guard call.duration >= minimum, !state.handled.contains(call.id) else {
        return .nothing
      }
      if let asked = state.lastAskedAt, calendar.isDate(asked, inSameDayAs: call.endedAt) {
        return .nothing
      }
      let quiet = isQuiet(call.endedAt)
      state.handled.append(call.id)
      if state.handled.count > Self.remembered {
        state.handled.removeFirst(state.handled.count - Self.remembered)
      }
      state.pendingUnseen = quiet ? true : nil
      state.askedBeforeUnseen = quiet ? state.lastAskedAt : nil
      state.pendingCallId = call.id
      state.pendingEndedAt = call.endedAt
      state.lastAskedAt = call.endedAt
      store.save(state)
      return quiet ? .askOnNextOpen : .notifyNow
    }
  }

  /// The prompt for her screen while a call is waiting for an answer, otherwise nil.
  public func promptToShow(at now: Date) -> String? {
    lock.withLock {
      var state = store.load()
      if dropExpired(&state, now: now) {
        store.save(state)
        return nil
      }
      guard state.pendingEndedAt != nil else { return nil }
      // It is on her screen now, so it counts as that day's one from here on.
      if state.pendingUnseen != nil {
        state.pendingUnseen = nil
        state.askedBeforeUnseen = nil
        store.save(state)
      }
      return Self.prompt
    }
  }

  /// When to post the daily prompt: `DailyCheckIn.schedule`, skipping the day a call was asked about.
  public func dailyCheckIns(_ settings: DailyCheckInSettings, now: Date) -> [DateComponents] {
    let asked = lock.withLock {
      var state = store.load()
      if dropExpired(&state, now: now) { store.save(state) }
      return state.lastAskedAt
    }
    return DailyCheckIn.schedule(settings, now: now, lastCallFollowUpAt: asked, calendar: calendar)
  }

  /// "わかった": the prompt closes and nothing else happens. No consultation, nothing to the family.
  public func acknowledged() {
    clearPending()
  }

  /// She started talking to the microphone; the prompt has done its job.
  public func consultStarted() {
    clearPending()
  }

  /// Forgets only which day a call was last asked about, so the next long call today is asked about
  /// again. For filming the demo more than once a day (a Debug launch argument,
  /// `-mimamori-followup-reset`); the calls already asked about and a waiting prompt stay.
  public func resetDailyLimit() {
    lock.withLock {
      var state = store.load()
      state.lastAskedAt = nil
      store.save(state)
    }
  }

  /// This iPhone is no longer in a family ("すべて消す", a 401, or leaving): the waiting prompt and
  /// what was asked go with the key.
  public func forget() {
    lock.withLock { store.clear() }
  }

  private func clearPending() {
    lock.withLock {
      var state = store.load()
      state.pendingCallId = nil
      state.pendingEndedAt = nil
      state.pendingUnseen = nil
      state.askedBeforeUnseen = nil
      store.save(state)
    }
  }

  /// Drops a waiting prompt older than `promptLifetime`. One left for the night and never on her
  /// screen gives that day back. True when something changed.
  private func dropExpired(_ state: inout CallFollowUpState, now: Date) -> Bool {
    guard let endedAt = state.pendingEndedAt, now.timeIntervalSince(endedAt) >= Self.promptLifetime
    else { return false }
    if state.pendingUnseen == true { state.lastAskedAt = state.askedBeforeUnseen }
    state.pendingCallId = nil
    state.pendingEndedAt = nil
    state.pendingUnseen = nil
    state.askedBeforeUnseen = nil
    return true
  }

  private func isQuiet(_ date: Date) -> Bool {
    Self.isQuiet(hour: calendar.component(.hour, from: date))
  }

  /// 22:00 up to 7:00. The one definition for both prompts.
  static func isQuiet(hour: Int) -> Bool {
    hour >= quietFrom || hour < quietUntil
  }
}
