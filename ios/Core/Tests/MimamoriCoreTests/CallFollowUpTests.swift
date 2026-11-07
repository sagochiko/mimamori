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

  @Test("忘れると、待っていた問いかけも、聞いた日の記録も消える(すべて消す、401、家族を抜けたとき)")
  func forgetClearsEverything() {
    let (followUp, store) = make()
    #expect(followUp.callEnded(Self.call(minutes: 10)) == .notifyNow)
    #expect(followUp.promptToShow(at: Self.at(15, 1)) == CallFollowUp.prompt)

    followUp.forget()

    #expect(followUp.promptToShow(at: Self.at(15, 1)) == nil)
    #expect(store.load() == CallFollowUpState())
  }

  @Test("3分以上の通話が終わったら1回だけ通知で声をかける")
  func longCallAsksOnce() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call(minutes: 3)) == .notifyNow)
    #expect(followUp.promptToShow(at: Self.at(15, 1)) == CallFollowUp.prompt)
  }

  @Test("声かけは問いかけにしない(2026年11月7日に作者が決めた、#123)")
  func promptIsNotAQuestion() {
    #expect(CallFollowUp.prompt == "知らない人や勧誘の電話で困ったら教えてね")
    #expect(!CallFollowUp.prompt.contains("？"))
    #expect(!CallFollowUp.prompt.contains("?"))
    // A short line on her screen carries no joining comma (CLAUDE.md, the copy rules).
    #expect(!CallFollowUp.prompt.contains("、"))
  }

  @Test("同じ日の2本目の長い通話のあとは声をかけない(1日1回まで)")
  func onceADay() {
    let (followUp, store) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(11))) == .notifyNow)
    let afterFirst = store.load()
    #expect(followUp.callEnded(Self.call("c2", minutes: 30, endedAt: Self.at(21, 59))) == .nothing)
    // The skipped call changes nothing: the first prompt still waits, and the day it was asked stays.
    #expect(store.load() == afterFirst)
    #expect(followUp.promptToShow(at: Self.at(22)) == CallFollowUp.prompt)
  }

  @Test("声かけを閉じたあとでも、同じ日の次の通話では声をかけない")
  func onceADayEvenAfterClosing() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(9)))
    followUp.acknowledged()
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(16))) == .nothing)
    #expect(followUp.promptToShow(at: Self.at(16, 1)) == nil)
  }

  @Test("夜に残した声かけも、画面で待っているあいだはその日の1回に数える")
  func nightPromptCountsForThatDay() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(0, 30))) == .askOnNextOpen)
    // 12:00 is before the 12 hours run out, so the prompt still waits for her.
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(12))) == .nothing)
  }

  @Test("夜に残した声かけが見られないまま12時間で消えたら、その日の1回に数えない(見逃しは誤報より重い)")
  func unseenNightPromptDoesNotCount() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(0, 30))) == .askOnNextOpen)
    // She does not open the app until after 12:30, so the prompt goes without being seen.
    #expect(followUp.promptToShow(at: Self.at(12, 31)) == nil)
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(15))) == .notifyNow)
  }

  @Test("夜に残した声かけは、アプリを開かないまま次の通話が来ても、消えたあとなら数えない")
  func unseenNightPromptDoesNotCountWithoutOpening() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(0, 30))) == .askOnNextOpen)
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(15))) == .notifyNow)
  }

  @Test("見られないまま消えた夜の声かけは、その日の毎日の声かけも外さない")
  func unseenNightPromptKeepsTheDailyPrompt() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(0, 30)))
    let slots = followUp.dailyCheckIns(.standard, now: Self.at(12, 31))
    #expect(slots.first == DailyCheckInTests.slot(day: 4, hour: 18))
  }

  @Test("夜に残した声かけを一度でも画面に出したら、消えてもその日の1回に数える")
  func seenNightPromptCounts() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(0, 30))) == .askOnNextOpen)
    #expect(followUp.promptToShow(at: Self.at(8)) == CallFollowUp.prompt)
    #expect(followUp.promptToShow(at: Self.at(12, 31)) == nil)
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(15))) == .nothing)
  }

  @Test("通知で出した声かけは、消えてもその日の1回に数える")
  func notifiedPromptCountsAfterExpiry() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(7))) == .notifyNow)
    #expect(followUp.promptToShow(at: Self.at(19, 1)) == nil)
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(20))) == .nothing)
  }

  @Test("日付が変われば、23時59分のあとの0時1分の通話でもまた声をかける")
  func newDayAtMidnight() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(23, 59))) == .askOnNextOpen)
    // 0:01 is in the quiet hours, so it waits on her screen rather than notifying.
    #expect(
      followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(0, 1, day: 5))) == .askOnNextOpen)
    #expect(followUp.callEnded(Self.call("c3", minutes: 5, endedAt: Self.at(12, day: 5))) == .nothing)
  }

  @Test("1日1回の記録だけを消すと、同じ日の次の通話でもまた声をかける(デモを撮り直す Debug の起動の引数)")
  func resetDailyLimitAllowsAnotherToday() {
    let (followUp, store) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(10))) == .notifyNow)
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(11))) == .nothing)

    followUp.resetDailyLimit()

    let state = store.load()
    #expect(state.lastAskedAt == nil)
    // Only the day's record goes: the calls already asked about and the waiting prompt stay.
    #expect(state.handled == ["c1"])
    #expect(state.pendingCallId == "c1")
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(12))) == .nothing)
    #expect(followUp.callEnded(Self.call("c3", minutes: 5, endedAt: Self.at(12))) == .notifyNow)
    #expect(followUp.callEnded(Self.call("c4", minutes: 5, endedAt: Self.at(13))) == .nothing)
  }

  @Test("次の日の同じ時刻なら、また通知で声をかける")
  func nextDaySameHour() {
    let (followUp, _) = make()
    #expect(followUp.callEnded(Self.call("c1", minutes: 5, endedAt: Self.at(15))) == .notifyNow)
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(15, day: 5))) == .notifyNow)
  }

  @Test("1日の区切りは端末の暦で数える(東京の0時は UTC では前の日)")
  func dayFollowsTheDeviceCalendar() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    // 東京の23時59分と次の日の0時1分は、UTC ではどちらも同じ日の14時台になる。
    let first = Self.call("c1", minutes: 5, endedAt: Self.at(23, 59))
    let second = Self.call("c2", minutes: 5, endedAt: Self.at(0, 1, day: 5))

    let inUTC = CallFollowUp(store: InMemoryCallFollowUpStore(), calendar: utc)
    #expect(inUTC.callEnded(first) == .notifyNow)
    #expect(inUTC.callEnded(second) == .nothing)

    let (inTokyo, _) = make()
    #expect(inTokyo.callEnded(first) != .nothing)
    #expect(inTokyo.callEnded(second) != .nothing)
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
    // The next day, so only the call's own id keeps it from being asked about again.
    #expect(followUp.callEnded(Self.call(minutes: 10, endedAt: Self.at(15, day: 5))) == .nothing)
  }

  @Test("別の日の別の通話ならまた声をかける")
  func anotherCallAsks() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call("c1", minutes: 5))
    followUp.acknowledged()
    #expect(followUp.callEnded(Self.call("c2", minutes: 5, endedAt: Self.at(16, day: 5))) == .notifyNow)
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

  @Test("「わかった」を押したら閉じるだけ(もう出さず、相談も家族への知らせもしない)")
  func acknowledgedDoesNothing() {
    let (followUp, _) = make()
    _ = followUp.callEnded(Self.call(minutes: 5))
    followUp.acknowledged()
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

  @Test("12時間たった声かけは出さない(電話から時間がたつと声かけの意味が薄れる)")
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
    #expect(reopened.callEnded(Self.call(minutes: 5, endedAt: Self.at(23, day: 5))) == .nothing)
  }

  @Test("覚える通話の数には上限がある")
  func remembersBoundedNumber() {
    let (followUp, store) = make()
    // One call a day, so each one is asked about and remembered (only one a day is, #123).
    for i in 0..<200 {
      #expect(
        followUp.callEnded(
          Self.call("c\(i)", minutes: 5, endedAt: Self.at(15).addingTimeInterval(Double(i) * 86_400)))
          == .notifyNow)
    }
    #expect(store.load().handled.count <= CallFollowUp.remembered)
  }
}
