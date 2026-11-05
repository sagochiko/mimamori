import Foundation
import Testing

@testable import MimamoriCore

@Suite("答えの読み上げの切り替え")
struct ReadAloudTests {
  static let answer = ConsultAnswer(reply: "設定の「一般」から", speak: "設定の一般から", tap: nil, handoff: false)

  @Test("既定はオフで、声で聞いても読み上げない")
  func offByDefault() {
    #expect(ReadAloudSettings.standard == ReadAloudSettings(isOn: false))
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("ストレージがいっぱい", isFinal: true, at: .t0 + 1)
    #expect(flow.answered(Self.answer).isEmpty)
    #expect(flow.phase == .answered(said: "ストレージがいっぱい", answer: Self.answer))
  }

  @Test("オンにしたら、声で聞いたときに読み上げる")
  func onSpeaksVoice() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("ストレージがいっぱい", isFinal: true, at: .t0 + 1)
    #expect(flow.answered(Self.answer, readsAloud: true) == [.speak("設定の一般から")])
  }

  @Test("オンでも、文字で聞いたときは読み上げない")
  func onDoesNotSpeakTyped() {
    var flow = VoiceConsult()
    _ = flow.typed("ストレージがいっぱい", at: .t0)
    #expect(flow.answered(Self.answer, readsAloud: true).isEmpty)
  }

  @Test("設定に何も書かれていなければオフ。書かれた値は Bool でも NSNumber でも読む")
  func readsSettings() {
    #expect(ReadAloudSettings(reading: { _ in nil }) == .standard)
    let on: [String: Any] = [ReadAloudSettings.enabledKey: NSNumber(value: true)]
    #expect(ReadAloudSettings(reading: { on[$0] }).isOn)
    let flag: [String: Any] = [ReadAloudSettings.enabledKey: true]
    #expect(ReadAloudSettings(reading: { flag[$0] }).isOn)
    let off: [String: Any] = [ReadAloudSettings.enabledKey: false]
    #expect(!ReadAloudSettings(reading: { off[$0] }).isOn)
  }

  @Test("iOS の「設定」の切り替えは、鍵と既定がこの決まりと同じで、名札は1語")
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
    let toggle = try #require(specifiers.first { $0["Key"] as? String == ReadAloudSettings.enabledKey })
    #expect(toggle["Type"] as? String == "PSToggleSwitchSpecifier")
    #expect(toggle["Title"] as? String == "読み上げ")
    #expect(toggle["DefaultValue"] as? Bool == false)
    #expect(toggle["DefaultValue"] as? Bool == ReadAloudSettings.standard.isOn)
  }
}
