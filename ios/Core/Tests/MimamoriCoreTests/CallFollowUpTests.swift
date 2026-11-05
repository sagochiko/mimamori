import Foundation
import Testing

@testable import MimamoriCore

@Suite("通話のあとの声かけ")
struct CallFollowUpTests {
  static let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }()

  /// 2026年11月4日の、東京の時刻で hour:minute。
  static func at(_ hour: Int, _ minute: Int = 0, day: Int = 4) -> Date {
    tokyo.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  static func call(_ id: String = "c1", minutes: Double, endedAt: Date = at(15)) -> EndedCall {
    EndedCall(id: id, duration: minutes * 60, endedAt: endedAt)
  }

  func make() -> (CallFollowUp, InMemoryCallFollowUpStore) {
    let store = InMemoryCallFollowUpStore()
    return (CallFollowUp(store: store, calendar: Self.tokyo), store)
  }

  @Test("3分以上の通話が終わったら1回だけ通知で聞く")
  func longCallAsksOnce() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call(minutes: 3)) == .notifyNow)
    #expect(CallFollowUp.prompt == "さっきの電話、大丈夫だった？")
    #expect(followUp.promptToShow(at: Self.at(15, 1)) == CallFollowUp.prompt)
  }

  @Test("3分未満なら聞かない")
  func shortCallIsQuiet() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call(minutes: 2.99)) == .nothing)
    #expect(followUp.promptToShow(at: Self.at(15, 1)) == nil)
  }

  @Test("既定の下限は3分のまま")
  func defaultMinimumIsThreeMinutes() {
    #expect(CallFollowUp.minimumDuration == 180)
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call(minutes: 0.5)) == .nothing)
  }

  @Test("下限を短くすれば、短い通話でも聞く(デモを撮るときの Debug の起動の引数)")
  func shorterMinimum() {
    let followUp = CallFollowUp(store: InMemoryCallFollowUpStore(), calendar: Self.tokyo, minimumDuration: 10)
    #expect(followUp.callEnded(EndedCall(id: "short", duration: 9.9, endedAt: Self.at(15))) == .nothing)
    #expect(followUp.callEnded(EndedCall(id: "demo", duration: 15, endedAt: Self.at(15))) == .notifyNow)
  }

  @Test("同じ通話で2回は聞かない")
  func sameCallOnce() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call(minutes: 10)) == .notifyNow)
    #expect(followUp.callEnded(Self.call(minutes: 10, endedAt: Self.at(15, 1))) == .nothing)
  }

  @Test("別の通話ならまた聞く")
  func anotherCallAsks() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call("c1", minutes: 5))
    followUp.answeredFine()
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(16))) == .notifyNow)
  }

  @Test("夜22時から朝7時は通知を出さず、次にアプリを開いたときに聞く", arguments: [(22, 0), (23, 30), (0, 0), (6, 59)])
  func quietHours(hour: Int, minute: Int) {
    let (followUp, _) = make()
    let ended = Self.at(hour, minute)
    #expect(followUp.callEnded(Self.call(minutes: 20, endedAt: ended)) == .askOnNextOpen)
    #expect(followUp.promptToShow(at: ended.addingTimeInterval(8 * 3600)) == CallFollowUp.prompt)
  }

  @Test("21時59分と朝7時は通知する", arguments: [(21, 59), (7, 0)])
  func edgesOfQuietHours(hour: Int, minute: Int) {
    let (followUp, _) = make()
    #expect(
      followUp.callEnded(Self.call(minutes: 20, endedAt: Self.at(hour, minute))) == .notifyNow)
  }

  @Test("「大丈夫」を押したら何もしない(もう聞かず、相談も家族への知らせもしない)")
  func fineDoesNothing() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call(minutes: 5))
    followUp.answeredFine()
    #expect(followUp.promptToShow(at: Self.at(15, 1)) == nil)
    #expect(followUp.callEnded(Self.call(minutes: 5)) == .nothing)
  }

  @Test("相談を始めたら声かけは消える")
  func consultClears() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call(minutes: 5))
    followUp.consultStarted()
    #expect(followUp.promptToShow(at: Self.at(15, 1)) == nil)
  }

  @Test("12時間たった声かけは出さない(「さっきの電話」と言えなくなる)")
  func oldPromptExpires() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call(minutes: 5, endedAt: Self.at(23)))
    #expect(followUp.promptToShow(at: Self.at(10, 59, day: 5)) == CallFollowUp.prompt)
    #expect(followUp.promptToShow(at: Self.at(11, 0, day: 5)) == nil)
  }

  @Test("覚えたことはアプリを開き直しても残る")
  func persists() {
    let store = InMemoryCallFollowUpStore()
    _ = CallFollowUp(store: store, calendar: Self.tokyo).callEnded(
      Self.call(minutes: 5, endedAt: Self.at(23)))
    let reopened = CallFollowUp(store: store, calendar: Self.tokyo)
    #expect(reopened.promptToShow(at: Self.at(8, day: 5)) == CallFollowUp.prompt)
    #expect(reopened.callEnded(Self.call(minutes: 5, endedAt: Self.at(23))) == .nothing)
  }

  @Test("覚える通話の数には上限がある")
  func remembersBoundedNumber() {
    let (followUp, store) = make()
    for i in 0..<200 {
      _ = followUp.callEnded(
        Self.call("c\(i)", minutes: 5, endedAt: Self.at(15).addingTimeInterval(Double(i))))
    }
    #expect(store.load().handled.count <= CallFollowUp.remembered)
  }
}
