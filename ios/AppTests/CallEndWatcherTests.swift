import Foundation
import MimamoriCore
import Testing

@testable import Mimamori

/// The call watch on her iPhone (#99). CXCallObserver cannot be made to report a call in a test, so
/// a fake list stands in for its `calls`, and the changes are passed the way the delegate passes them.
@MainActor
struct CallEndWatcherTests {
  final class FakeCalls: CallList {
    var current: [(id: String, hasConnected: Bool, hasEnded: Bool)] = []
  }

  final class Ended {
    var calls: [EndedCall] = []
  }

  static let t0 = Date(timeIntervalSince1970: 1_793_000_000)

  private let fake = FakeCalls()
  private let ended = Ended()

  private func makeWatcher() -> (CallEndWatcher, () -> Int) {
    let fake = fake
    let ended = ended
    final class Count { var value = 0 }
    let count = Count()
    let watcher = CallEndWatcher(
      onEnded: { ended.calls.append($0) },
      makeObserver: { _ in
        count.value += 1
        return fake
      })
    return (watcher, { count.value })
  }

  @Test("アプリを閉じているあいだに出た電話の途中で開き、そのまま前面で切れたら声かけに渡す")
  func reopenedDuringACall() {
    let (watcher, made) = makeWatcher()
    // She opened the app once, then went home. Nothing was going on.
    watcher.start(at: Self.t0)
    // While the app was suspended she answered a call; no change reached the app.
    fake.current = [(id: "a", hasConnected: true, hasEnded: false)]
    // Worried in the middle of the call, she opens the app again.
    watcher.start(at: Self.t0.addingTimeInterval(60))
    // The call ends while the app is in front.
    watcher.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.t0.addingTimeInterval(300))

    #expect(ended.calls == [EndedCall(id: "a", duration: 240, endedAt: Self.t0.addingTimeInterval(300))])
    #expect(made() == 1)
  }

  @Test("測っている通話は、開き直しても始まりを動かさない")
  func reopeningKeepsTheStart() {
    let (watcher, _) = makeWatcher()
    watcher.start(at: Self.t0)
    watcher.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.t0.addingTimeInterval(10))
    fake.current = [(id: "a", hasConnected: true, hasEnded: false)]
    watcher.start(at: Self.t0.addingTimeInterval(100))
    watcher.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.t0.addingTimeInterval(250))

    #expect(ended.calls.map(\.duration) == [240])
  }

  @Test("役を抜けたら、そのあとの通話の終わりは渡さない")
  func stoppedIgnoresChanges() {
    let (watcher, _) = makeWatcher()
    watcher.start(at: Self.t0)
    watcher.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.t0)
    watcher.stop()
    watcher.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.t0.addingTimeInterval(300))

    #expect(ended.calls.isEmpty)
  }
}
