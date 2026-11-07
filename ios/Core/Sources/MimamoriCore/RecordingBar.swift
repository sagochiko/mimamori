import Foundation

// The field while the microphone listens (#224), shaped like the recording field of the usual chat
// apps: trash, the time since listening started, dots that follow her voice, stop, send. The App draws
// it; the numbers and the words for VoiceOver are here so they can be tested. The buttons show no text.

/// The elapsed time beside the dots, "0:05".
public enum RecordingClock {
  public static func text(elapsed: TimeInterval) -> String {
    let seconds = max(0, Int(elapsed.rounded(.down)))
    let rest = seconds % 60
    return "\(seconds / 60):\(rest < 10 ? "0" : "")\(rest)"
  }

  /// For VoiceOver: "5秒", "1分2秒".
  public static func spoken(elapsed: TimeInterval) -> String {
    let seconds = max(0, Int(elapsed.rounded(.down)))
    let minutes = seconds / 60
    let rest = seconds % 60
    if minutes == 0 { return "\(rest)秒" }
    return rest == 0 ? "\(minutes)分" : "\(minutes)分\(rest)秒"
  }
}

/// How loud her voice was lately, one value from 0 to 1 per dot, oldest on the left. Fed from the
/// microphone's input on the iPhone; the values are only drawn and never leave the phone.
public struct VoiceLevels: Equatable, Sendable {
  /// Quieter than this is drawn as silence.
  public static let floorDecibels: Double = -50

  public private(set) var values: [Double]

  public init(count: Int = 24) {
    values = Array(repeating: 0, count: max(1, count))
  }

  /// The root mean square of one buffer of samples (full scale is 1), from -50 dB to 0 dB as 0 to 1.
  public static func normalized(rms: Double) -> Double {
    guard rms > 0 else { return 0 }
    let decibels = 20 * log10(rms)
    return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
  }

  public mutating func add(rms: Double) {
    values.removeFirst()
    values.append(Self.normalized(rms: rms))
  }

  public mutating func reset() {
    values = Array(repeating: 0, count: values.count)
  }
}

/// VoiceOver's words for the recording field.
public enum RecordingBar {
  public static let discardLabel = "やめる"
  public static let discardHint = "聞いた言葉を捨てて、何も送りません"
  public static let stopLabel = "止める"
  public static let stopHint = "聞くのをやめて、聞いた言葉を欄に入れます。直してから送れます"
  public static let sendLabel = "送る"
  public static let sendHint = "聞いた言葉をそのまま送ります。話し終わって少し黙っても、自動で送ります"
  public static let levelsLabel = "声の大きさ"

  public static func clockLabel(elapsed: TimeInterval) -> String {
    "聞いています、\(RecordingClock.spoken(elapsed: elapsed))"
  }
}
