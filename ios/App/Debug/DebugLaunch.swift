#if DEBUG
  import Foundation

  /// Debug builds only: launch arguments for filming the demo and for the simulator. Release builds
  /// never contain this code, so the 3-minute minimum and the chosen hour always hold there.
  enum DebugLaunch {
    /// `-mimamori-followup-min-seconds <n>`: ask after a call of n seconds or more instead of 3
    /// minutes, so the demo can be filmed with a 15 to 60 second call.
    static var followUpMinimum: TimeInterval? { seconds(after: "-mimamori-followup-min-seconds") }

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

    private static func seconds(after flag: String) -> TimeInterval? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: flag), i + 1 < args.count,
        let value = TimeInterval(args[i + 1]), value >= 0
      else { return nil }
      return value
    }
  }
#endif
