import Foundation

// The daily "今日、知らない人から電話や連絡はあった？" (#99). The app learns of a call only while it is
// in front (#25), so once a day the app asks on its own, and a tap opens her chat. Decided by the
// author on 2026年11月5日, together with the switch and the hour in iOS Settings (Settings.bundle).

/// What she (or the family, on her iPhone) chose in Settings > みまもり.
public struct DailyCheckInSettings: Equatable, Sendable {
  public var isOn: Bool
  /// Hour of the day, device time. One of `hours`.
  public var hour: Int

  /// The choices in Settings. None falls in 22:00 to 7:00. 18:00 is the default so a call from that
  /// day is talked about before a transfer the next morning (the author, 2026年11月5日).
  public static let hours = [17, 18, 19, 20, 21]
  public static let defaultHour = 18
  public static let standard = DailyCheckInSettings(isOn: true, hour: defaultHour)

  /// The keys in ios/App/Settings.bundle/Root.plist.
  public static let enabledKey = "dailyCheckInEnabled"
  public static let hourKey = "dailyCheckInHour"

  public init(isOn: Bool, hour: Int) {
    self.isOn = isOn
    self.hour = hour
  }

  /// Reads what Settings wrote. iOS writes nothing until the person opens that screen once, so a
  /// missing key means the default; so does an hour that is not one of the choices.
  public init(reading value: (String) -> Any?) {
    let on: Bool? =
      switch value(Self.enabledKey) {
      case let flag as Bool: flag
      case let number as NSNumber: number.boolValue
      default: nil
      }
    let hour: Int? =
      switch value(Self.hourKey) {
      case let number as Int: number
      case let number as NSNumber: number.intValue
      case let text as String: Int(text)
      default: nil
      }
    self.isOn = on ?? Self.standard.isOn
    self.hour = hour.flatMap { Self.hours.contains($0) ? $0 : nil } ?? Self.defaultHour
  }
}

public enum DailyCheckIn {
  public static let prompt = "今日、知らない人から電話や連絡はあった？"
  /// One notification per day for this many days from today, rebuilt each time the app comes to the
  /// front. A repeating trigger cannot skip the day a call was already asked about, so each day is
  /// its own request. iOS keeps only so many pending local notifications (UILocalNotification's
  /// documentation names the soonest 64; UNUserNotificationCenter's names no number), so this stays
  /// at half of that and leaves room for the other prompts. If she opens the app less than once a
  /// month, the prompt stops until she does.
  public static let daysAhead = 30

  /// The days and hour to ask, soonest first, as year, month, day, hour and minute in `calendar`
  /// (what UNCalendarNotificationTrigger takes). Empty when off, or when the hour is in 22:00 to
  /// 7:00. Today counts only while its hour is still ahead; the day of `lastCallFollowUpAt` is left
  /// out, since she was already asked about a call that day.
  public static func schedule(
    _ settings: DailyCheckInSettings, now: Date, lastCallFollowUpAt: Date?, calendar: Calendar
  ) -> [DateComponents] {
    guard settings.isOn, !CallFollowUp.isQuiet(hour: settings.hour) else { return [] }
    let today = calendar.startOfDay(for: now)
    return (0..<daysAhead).compactMap { offset in
      guard let day = calendar.date(byAdding: .day, value: offset, to: today),
        let fire = calendar.date(bySettingHour: settings.hour, minute: 0, second: 0, of: day),
        fire > now
      else { return nil }
      if let asked = lastCallFollowUpAt, calendar.isDate(asked, inSameDayAs: fire) { return nil }
      return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
    }
  }
}
