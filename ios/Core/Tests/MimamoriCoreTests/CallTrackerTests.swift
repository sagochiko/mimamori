import Foundation
import Testing

@testable import MimamoriCore

@Suite("通話の長さを測る")
struct CallTrackerTests {
  static let start = Date(timeIntervalSince1970: 1_793_000_000)
  static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

  @Test("つながってから終わるまでの長さで、終わった通話を返す")
  func connectedThenEnded() {
    var tracker = CallTracker()
    #expect(tracker.changed(id: "a", hasConnected: false, hasEnded: false, at: Self.at(0)) == nil)
    #expect(tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(10)) == nil)
    let ended = tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(250))
    #expect(ended == EndedCall(id: "a", duration: 240, endedAt: Self.at(250)))
  }

  @Test("つながらずに終わった通話(出なかった、断った)は返さない")
  func neverConnected() {
    var tracker = CallTracker()
    _ = tracker.changed(id: "a", hasConnected: false, hasEnded: false, at: Self.at(0))
    #expect(tracker.changed(id: "a", hasConnected: false, hasEnded: true, at: Self.at(30)) == nil)
  }

  @Test("つながったあとの知らせ(保留など)が何度来ても、始まりは最初につながったとき")
  func repeatedConnectedKeepsStart() {
    var tracker = CallTracker()
    _ = tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(0))
    _ = tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(60))
    _ = tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(120))
    #expect(
      tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(200))?.duration
        == 200)
  }

  @Test("見始めたときにもうつながっていた通話は、見始めたときから数える(短めに数える)")
  func alreadyConnectedCountsFromNow() {
    var tracker = CallTracker()
    tracker.started(with: [(id: "a", hasConnected: true, hasEnded: false)], at: Self.at(100))
    #expect(
      tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(130))?.duration == 30
    )
  }

  @Test("同じ通話の終わりが2回来ても、2回は返さない")
  func endedOnce() {
    var tracker = CallTracker()
    _ = tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(0))
    #expect(tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(200)) != nil)
    #expect(tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(201)) == nil)
  }

  @Test("2本の通話は別々に測る(キャッチホン)")
  func twoCalls() {
    var tracker = CallTracker()
    _ = tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(0))
    _ = tracker.changed(id: "b", hasConnected: true, hasEnded: false, at: Self.at(50))
    #expect(
      tracker.changed(id: "b", hasConnected: true, hasEnded: true, at: Self.at(80))?.duration == 30)
    #expect(
      tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(300))?.duration
        == 300)
  }

  @Test("見るのをやめたら、測りかけの通話は忘れる")
  func stopForgets() {
    var tracker = CallTracker()
    _ = tracker.changed(id: "a", hasConnected: true, hasEnded: false, at: Self.at(0))
    tracker.stop()
    #expect(tracker.changed(id: "a", hasConnected: true, hasEnded: true, at: Self.at(300)) == nil)
  }
}
