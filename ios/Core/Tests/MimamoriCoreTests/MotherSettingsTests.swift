import Foundation
import Testing

@testable import MimamoriCore

// The settings screen inside the app (#222) writes the same keys as Settings > みまもり, so a value
// set in one shows in the other.
@Suite("アプリの中の設定の画面")
struct MotherSettingsTests {
  @Test("毎日の声かけの値を書いて読み直すと同じになる", arguments: [true, false], DailyCheckInSettings.hours)
  func dailyRoundTrip(isOn: Bool, hour: Int) {
    let settings = DailyCheckInSettings(isOn: isOn, hour: hour)
    let stored = settings.stored
    #expect(Set(stored.keys) == [DailyCheckInSettings.enabledKey, DailyCheckInSettings.hourKey])
    #expect(DailyCheckInSettings(reading: { stored[$0] }) == settings)
  }

  @Test("毎日の声かけの時刻は数で書く(「設定」の Values と同じ型)")
  func hourIsStoredAsNumber() {
    let stored = DailyCheckInSettings(isOn: true, hour: 20).stored
    #expect(stored[DailyCheckInSettings.hourKey] as? Int == 20)
    #expect(stored[DailyCheckInSettings.enabledKey] as? Bool == true)
  }

  @Test("読み上げの値を書いて読み直すと同じになる", arguments: [true, false])
  func readAloudRoundTrip(isOn: Bool) {
    let stored = ReadAloudSettings(isOn: isOn).stored
    #expect(Set(stored.keys) == [ReadAloudSettings.enabledKey])
    #expect(stored[ReadAloudSettings.enabledKey] as? Bool == isOn)
    #expect(ReadAloudSettings(reading: { stored[$0] }) == ReadAloudSettings(isOn: isOn))
  }

  @Test("時刻の名札は「設定」の Titles と同じ")
  func hourLabelsMatchSettingsBundle() throws {
    let plist = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "App/Settings.bundle/Root.plist")
    let data = try Data(contentsOf: plist)
    let root = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let specifiers = try #require(root["PreferenceSpecifiers"] as? [[String: Any]])
    let hour = try #require(specifiers.first { $0["Key"] as? String == DailyCheckInSettings.hourKey })
    let titles = try #require(hour["Titles"] as? [String])
    #expect(DailyCheckInSettings.hours.map(DailyCheckInSettings.label(for:)) == titles)
    #expect(DailyCheckInSettings.label(for: 18) == "18時")
  }

  @Test("画面の名札は「設定」の名札と同じ1語")
  func titlesMatchSettingsBundle() throws {
    let plist = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "App/Settings.bundle/Root.plist")
    let data = try Data(contentsOf: plist)
    let root = try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let specifiers = try #require(root["PreferenceSpecifiers"] as? [[String: Any]])
    func title(_ key: String) -> String? {
      specifiers.first { $0["Key"] as? String == key }?["Title"] as? String
    }
    #expect(title(DailyCheckInSettings.enabledKey) == DailyCheckInSettings.title)
    #expect(title(DailyCheckInSettings.hourKey) == DailyCheckInSettings.hourTitle)
    #expect(title(ReadAloudSettings.enabledKey) == ReadAloudSettings.title)
    #expect(DailyCheckInSettings.title == "毎日の声かけ")
    #expect(DailyCheckInSettings.hourTitle == "時刻")
    #expect(ReadAloudSettings.title == "読み上げ")
  }
}
