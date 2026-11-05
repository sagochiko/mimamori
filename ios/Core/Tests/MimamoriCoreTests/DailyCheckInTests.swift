import Foundation
import Testing

@testable import MimamoriCore

@Suite("毎日の声かけ")
struct DailyCheckInTests {
  static let tokyo = CallFollowUpTests.tokyo
  static func at(_ hour: Int, _ minute: Int = 0, day: Int = 4) -> Date {
    CallFollowUpTests.at(hour, minute, day: day)
  }

  /// y/m/d/h/m of 2026年11月の `day` 日の `hour` 時、`schedule` が返す形のまま。
  static func slot(day: Int, hour: Int) -> DateComponents {
    DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: 0)
  }

  static func schedule(
    _ settings: DailyCheckInSettings = .standard, now: Date, lastCallFollowUpAt: Date? = nil,
    calendar: Calendar = tokyo
  ) -> [DateComponents] {
    DailyCheckIn.schedule(
      settings, now: now, lastCallFollowUpAt: lastCallFollowUpAt, calendar: calendar)
  }

  @Test("文言は相談のきっかけで、「安全」とは言わない")
  func promptWording() {
    #expect(DailyCheckIn.prompt == "今日、知らない人から電話や連絡はあった？")
    #expect(!DailyCheckIn.prompt.contains("安全"))
  }

  @Test("既定はオンで18時")
  func defaults() {
    #expect(DailyCheckInSettings.standard == DailyCheckInSettings(isOn: true, hour: 18))
    #expect(DailyCheckInSettings.hours == [17, 18, 19, 20, 21])
  }

  @Test("オンなら、選んだ時刻に1日1回、今日から決まった日数ぶん")
  func oncePerDayAtChosenHour() {
    let slots = Self.schedule(DailyCheckInSettings(isOn: true, hour: 19), now: Self.at(9))
    #expect(slots.count == DailyCheckIn.daysAhead)
    #expect(slots.first == Self.slot(day: 4, hour: 19))
    #expect(slots.dropFirst().first == Self.slot(day: 5, hour: 19))
    #expect(slots.allSatisfy { $0.hour == 19 && $0.minute == 0 })
    // One per calendar day: no two slots on the same day, no day skipped.
    let days = slots.compactMap { Self.tokyo.date(from: $0) }.map { Self.tokyo.startOfDay(for: $0) }
    #expect(Set(days).count == slots.count)
    for (a, b) in zip(days, days.dropFirst()) {
      #expect(Self.tokyo.dateComponents([.day], from: a, to: b).day == 1)
    }
  }

  @Test("日数は、iOS が残すローカル通知の数より十分に少ない")
  func boundedWindow() {
    #expect(DailyCheckIn.daysAhead > 7)
    #expect(DailyCheckIn.daysAhead <= 32)
  }

  @Test("今日の時刻を過ぎていたら明日から(ちょうどの時刻も過ぎたとみなす)", arguments: [(18, 0), (18, 1), (21, 30)])
  func pastTodayStartsTomorrow(hour: Int, minute: Int) {
    let slots = Self.schedule(now: Self.at(hour, minute))
    #expect(slots.first == Self.slot(day: 5, hour: 18))
    #expect(slots.count == DailyCheckIn.daysAhead - 1)
  }

  @Test("17時59分なら今日の18時から")
  func justBefore() {
    #expect(Self.schedule(now: Self.at(17, 59)).first == Self.slot(day: 4, hour: 18))
  }

  @Test("オフなら出さない")
  func offIsQuiet() {
    #expect(Self.schedule(DailyCheckInSettings(isOn: false, hour: 18), now: Self.at(9)).isEmpty)
  }

  @Test("夜22時から朝7時の時刻は出さない", arguments: [22, 23, 0, 3, 6])
  func quietHoursNeverScheduled(hour: Int) {
    #expect(Self.schedule(DailyCheckInSettings(isOn: true, hour: hour), now: Self.at(9)).isEmpty)
  }

  @Test("選べる時刻は、どれも夜22時から朝7時に入らない")
  func choicesAreOutsideQuietHours() {
    for hour in DailyCheckInSettings.hours {
      #expect(!CallFollowUp.isQuiet(hour: hour))
    }
  }

  @Test("同じ日に通話のあとの声かけを出していたら、その日は出さない")
  func skipsDayOfCallFollowUp() {
    let slots = Self.schedule(now: Self.at(9), lastCallFollowUpAt: Self.at(8, 30))
    #expect(slots.first == Self.slot(day: 5, hour: 18))
    #expect(!slots.contains(Self.slot(day: 4, hour: 18)))
    #expect(slots.contains(Self.slot(day: 6, hour: 18)))
  }

  @Test("前の日の通話のあとの声かけは、今日の声かけを止めない")
  func yesterdaysFollowUpDoesNotSkipToday() {
    let slots = Self.schedule(now: Self.at(9), lastCallFollowUpAt: Self.at(23, day: 3))
    #expect(slots.first == Self.slot(day: 4, hour: 18))
  }

  @Test("日付はカレンダーのタイムゾーンで決まる")
  func timeZoneIsInjected() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    // 東京の11月4日 9:00 は、UTC では11月4日 0:00。
    let now = Self.at(9)
    let slots = Self.schedule(now: now, calendar: utc)
    #expect(slots.first == Self.slot(day: 4, hour: 18))
    // 東京の11月5日 8:00 は、UTC では11月4日 23:00 で、UTC の11月4日に出したことになる。
    let skipped = Self.schedule(now: now, lastCallFollowUpAt: Self.at(8, day: 5), calendar: utc)
    #expect(skipped.first == Self.slot(day: 5, hour: 18))
    // 東京で数えれば同じ日時は11月5日なので、4日は残る。
    let tokyoSlots = Self.schedule(now: now, lastCallFollowUpAt: Self.at(8, day: 5))
    #expect(tokyoSlots.first == Self.slot(day: 4, hour: 18))
    #expect(!tokyoSlots.contains(Self.slot(day: 5, hour: 18)))
  }

  // MARK: Settings

  @Test("設定に何も書かれていなければ、既定のオンと18時")
  func missingSettingsMeanDefaults() {
    let settings = DailyCheckInSettings(reading: { _ in nil })
    #expect(settings == .standard)
  }

  @Test("設定の値を読む(数は NSNumber でも文字でもよい)")
  func readsSettings() {
    let values: [String: Any] = [
      DailyCheckInSettings.enabledKey: NSNumber(value: false),
      DailyCheckInSettings.hourKey: NSNumber(value: 20),
    ]
    #expect(
      DailyCheckInSettings(reading: { values[$0] }) == DailyCheckInSettings(isOn: false, hour: 20))
    let strings: [String: Any] = [
      DailyCheckInSettings.enabledKey: true, DailyCheckInSettings.hourKey: "21",
    ]
    #expect(
      DailyCheckInSettings(reading: { strings[$0] }) == DailyCheckInSettings(isOn: true, hour: 21))
  }

  @Test("選べない時刻が入っていたら18時にする", arguments: [23, 3, 12, -1])
  func unknownHourFallsBack(hour: Int) {
    let values: [String: Any] = [DailyCheckInSettings.hourKey: hour]
    #expect(DailyCheckInSettings(reading: { values[$0] }).hour == DailyCheckInSettings.defaultHour)
  }

  @Test("iOS の「設定」に置く項目は、鍵、既定、選択肢がこの決まりと同じ")
  func settingsBundleMatches() throws {
    // ios/Core/Tests/MimamoriCoreTests/ から ios/App/Settings.bundle/Root.plist へ。
    let plist = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "App/Settings.bundle/Root.plist")
    let data = try Data(contentsOf: plist)
    let root = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let specifiers = try #require(root["PreferenceSpecifiers"] as? [[String: Any]])
    func specifier(_ key: String) throws -> [String: Any] {
      try #require(specifiers.first { $0["Key"] as? String == key })
    }

    let toggle = try specifier(DailyCheckInSettings.enabledKey)
    #expect(toggle["Type"] as? String == "PSToggleSwitchSpecifier")
    #expect(toggle["DefaultValue"] as? Bool == DailyCheckInSettings.standard.isOn)

    let hour = try specifier(DailyCheckInSettings.hourKey)
    #expect(hour["Type"] as? String == "PSMultiValueSpecifier")
    #expect(hour["DefaultValue"] as? Int == DailyCheckInSettings.defaultHour)
    let values = try #require(hour["Values"] as? [Int])
    #expect(values == DailyCheckInSettings.hours)
    let titles = try #require(hour["Titles"] as? [String])
    #expect(titles == values.map { "\($0)時" })
  }
}

@Suite("毎日の声かけと、通話のあとの声かけ")
struct DailyCheckInWithFollowUpTests {
  @Test("通話のあとの声かけを出した日は、その日の毎日の声かけを外す")
  func followUpRemovesToday() {
    let followUp = CallFollowUp(
      store: InMemoryCallFollowUpStore(), calendar: CallFollowUpTests.tokyo)
    let before = followUp.dailyCheckIns(.standard, now: CallFollowUpTests.at(10))
    #expect(before.first == DailyCheckInTests.slot(day: 4, hour: 18))

    #expect(
      followUp.callEnded(CallFollowUpTests.call(minutes: 5, endedAt: CallFollowUpTests.at(10)))
        == .notifyNow)
    let after = followUp.dailyCheckIns(.standard, now: CallFollowUpTests.at(10, 1))
    #expect(after.first == DailyCheckInTests.slot(day: 5, hour: 18))
  }

  @Test("夜中の通話で、次に開いたときに聞く日も外す")
  func nightFollowUpRemovesThatDay() {
    let followUp = CallFollowUp(
      store: InMemoryCallFollowUpStore(), calendar: CallFollowUpTests.tokyo)
    #expect(
      followUp.callEnded(CallFollowUpTests.call(minutes: 5, endedAt: CallFollowUpTests.at(0, 30)))
        == .askOnNextOpen)
    #expect(
      followUp.dailyCheckIns(.standard, now: CallFollowUpTests.at(7)).first
        == DailyCheckInTests.slot(day: 5, hour: 18))
  }

  @Test("短い通話で声かけを出さなかった日は、毎日の声かけを残す")
  func shortCallKeepsToday() {
    let followUp = CallFollowUp(
      store: InMemoryCallFollowUpStore(), calendar: CallFollowUpTests.tokyo)
    #expect(
      followUp.callEnded(CallFollowUpTests.call(minutes: 1, endedAt: CallFollowUpTests.at(10)))
        == .nothing)
    #expect(
      followUp.dailyCheckIns(.standard, now: CallFollowUpTests.at(10, 1)).first
        == DailyCheckInTests.slot(day: 4, hour: 18))
  }

  @Test("声かけを出した日は、アプリを開き直しても覚えている")
  func remembered() {
    let store = InMemoryCallFollowUpStore()
    _ = CallFollowUp(store: store, calendar: CallFollowUpTests.tokyo).callEnded(
      CallFollowUpTests.call(minutes: 5, endedAt: CallFollowUpTests.at(10)))
    let reopened = CallFollowUp(store: store, calendar: CallFollowUpTests.tokyo)
    #expect(
      reopened.dailyCheckIns(.standard, now: CallFollowUpTests.at(12)).first
        == DailyCheckInTests.slot(day: 5, hour: 18))
  }

  @Test("前の版で残した覚え書き(声かけの日が無い)も読める")
  func decodesOlderState() throws {
    let old = #"{"handled":["c1"],"pendingCallId":"c1","pendingEndedAt":0}"#
    let state = try JSONDecoder().decode(CallFollowUpState.self, from: Data(old.utf8))
    #expect(state.handled == ["c1"])
    #expect(state.lastAskedAt == nil)
  }
}
