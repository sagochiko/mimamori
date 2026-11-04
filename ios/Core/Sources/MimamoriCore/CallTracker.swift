import Foundation

/// Turns the call changes that CXCallObserver reports into ended calls with how long they were
/// connected (`hasConnected` until `hasEnded`). The App's adapter passes only the call's id and its
/// two flags: CXCall carries no phone number, and nothing about the call is logged or kept here once
/// it ends.
public struct CallTracker: Sendable {
  private var connectedAt: [String: Date] = [:]

  public init() {}

  /// The calls already under way when watching starts. A connected one counts from now, which is
  /// shorter than the real call: it may then not reach the minimum, but it never asks after a call
  /// that was shorter than the minimum.
  public mutating func started(
    with calls: [(id: String, hasConnected: Bool, hasEnded: Bool)], at now: Date
  ) {
    for call in calls {
      _ = changed(id: call.id, hasConnected: call.hasConnected, hasEnded: call.hasEnded, at: now)
    }
  }

  /// One `callChanged`. Returns the call once, when it ends after having been connected; a call that
  /// was never answered (missed, declined, or the other side did not pick up) returns nil.
  public mutating func changed(id: String, hasConnected: Bool, hasEnded: Bool, at now: Date)
    -> EndedCall?
  {
    if hasEnded {
      guard let start = connectedAt.removeValue(forKey: id) else { return nil }
      return EndedCall(id: id, duration: now.timeIntervalSince(start), endedAt: now)
    }
    if hasConnected, connectedAt[id] == nil { connectedAt[id] = now }
    return nil
  }

  /// Watching stopped (she left the family): calls being timed are forgotten.
  public mutating func stop() {
    connectedAt.removeAll()
  }
}
