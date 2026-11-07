import Foundation

// Reading the AI's answer aloud (#115). Off unless she, or the family on her iPhone, turns it on in
// Settings > みまもり (or, from 2026年11月7日, the app's own settings screen, #222): the author tried it on the iPhone on 2026年11月5日 and chose off as the default.
// Even when on, only an answer to a spoken question is read (VoiceConsult.answered).

/// What Settings > みまもり holds for 「読み上げ」.
public struct ReadAloudSettings: Equatable, Sendable {
  public var isOn: Bool

  public static let standard = ReadAloudSettings(isOn: false)

  /// The key in ios/App/Settings.bundle/Root.plist.
  public static let enabledKey = "readAloudEnabled"

  /// The name on the switch, in Settings > みまもり and on the app's own settings screen (#222).
  public static let title = "読み上げ"

  public init(isOn: Bool) {
    self.isOn = isOn
  }

  /// Reads what Settings wrote. iOS writes nothing until the person opens that screen once, so a
  /// missing key means the default (off).
  public init(reading value: (String) -> Any?) {
    let on: Bool? =
      switch value(Self.enabledKey) {
      case let flag as Bool: flag
      case let number as NSNumber: number.boolValue
      default: nil
      }
    self.isOn = on ?? Self.standard.isOn
  }

  /// What the app's settings screen writes (#222): the key and type Settings writes.
  public var stored: [String: Any] { [Self.enabledKey: isOn] }
}
