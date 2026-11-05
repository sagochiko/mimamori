import CallKit
import Foundation
import MimamoriCore

/// Hears the end of a call while the app is in front and hands it on as an `EndedCall` (#99).
/// `CallTracker` in Core does the timing; this only maps a `CXCall` to its id and two flags. A CXCall
/// carries no phone number, and nothing about a call is logged.
///
/// What #25 measured on the author's iPhone 16 (iOS 27.2) on 2026年11月5日: with the app in front,
/// `callChanged` came with `hasConnected`, then `hasEnded` 23 seconds later, both while the app was
/// active. After going home (and waiting 30 seconds) or swiping the app away, nothing came while the
/// call ended. Apple DTS says the same of suspended apps.
///
/// One observer is kept for as long as she is the protected member, also while the app is in the
/// background. A suspended app is told nothing, so keeping it costs nothing. Dropping it on the way
/// to the background would lose the call she took from inside the app: iOS brings the app back right
/// after the call screen closes, and whether an end that happened while suspended is delivered late
/// on resume was not measured (#25). If it is, the call counts up to that moment, which can only make
/// a call look longer than it was: she may be asked once too often, never too rarely.
@MainActor
final class CallEndWatcher: NSObject, CXCallObserverDelegate {
  private var observer: CXCallObserver?
  private var tracker = CallTracker()
  private let onEnded: (EndedCall) -> Void

  init(onEnded: @escaping (EndedCall) -> Void) {
    self.onEnded = onEnded
  }

  /// Safe to call every time the app comes to the front; only the first call makes the observer.
  func start() {
    guard observer == nil else { return }
    let observer = CXCallObserver()
    observer.setDelegate(self, queue: .main)
    self.observer = observer
    // A call already under way when she opened the app counts from now (CallTracker.started).
    tracker.started(
      with: observer.calls.map {
        (id: $0.uuid.uuidString, hasConnected: $0.hasConnected, hasEnded: $0.hasEnded)
      },
      at: .now)
  }

  /// She is no longer the protected member.
  func stop() {
    observer = nil
    tracker.stop()
  }

  nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    let id = call.uuid.uuidString
    let hasConnected = call.hasConnected
    let hasEnded = call.hasEnded
    let now = Date.now
    // The delegate queue is the main queue (start()).
    MainActor.assumeIsolated {
      guard observer != nil,
        let ended = tracker.changed(id: id, hasConnected: hasConnected, hasEnded: hasEnded, at: now)
      else { return }
      onEnded(ended)
    }
  }
}
