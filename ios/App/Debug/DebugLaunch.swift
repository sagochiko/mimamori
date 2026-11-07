#if DEBUG
  import Foundation

  /// Debug builds only: launch arguments for filming the demo and for the simulator. Release builds
  /// never contain this code, so the 3-minute minimum and the chosen hour always hold there.
  enum DebugLaunch {
    /// `-mimamori-followup-min-seconds <n>`: ask after a call of n seconds or more instead of 3
    /// minutes, so the demo can be filmed with a 15 to 60 second call.
    static var followUpMinimum: TimeInterval? { seconds(after: "-mimamori-followup-min-seconds") }

    /// `-mimamori-followup-reset`: at launch, forget which day the call follow-up was last shown, so
    /// a second take of the demo the same day gets the prompt again (`CallFollowUp.resetDailyLimit`).
    /// Her conversation and the device key stay.
    static var followUpReset: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-followup-reset") }

    /// `-mimamori-checkin-after-seconds <n>`: one daily prompt n seconds after the app first comes to
    /// the front (`DailyCheckInNotifier.postSoon`).
    static var checkInAfter: TimeInterval? { seconds(after: "-mimamori-checkin-after-seconds") }

    /// `-mimamori-free-bytes <n>`: the free space the checkup reads (#19). The simulator reads the
    /// Mac's disk, so without it the free-space prompt and the guide never show there.
    static var freeBytes: Int64? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: "-mimamori-free-bytes"), i + 1 < args.count,
        let value = Int64(args[i + 1]), value >= 0
      else { return nil }
      return value
    }

    /// `-mimamori-now-hour <0-23>`: the hour the checkups take as now (#19), so the free-space prompt
    /// can be filmed on the simulator at night, when it never shows (22:00 up to 7:00).
    static var nowHour: Int? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: "-mimamori-now-hour"), i + 1 < args.count,
        let value = Int(args[i + 1]), (0...23).contains(value)
      else { return nil }
      return value
    }

    private static func seconds(after flag: String) -> TimeInterval? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: flag), i + 1 < args.count,
        let value = TimeInterval(args[i + 1]), value >= 0
      else { return nil }
      return value
    }
  }
#endif
