import Foundation
import MimamoriCore
import UserNotifications

/// The daily "今日、知らない人から電話や連絡はあった？" (#99). `CallFollowUp.dailyCheckIns` in Core
/// decides the days; this swaps the pending requests for them. Tapping one opens the app, and her
/// screen is the chat, so she can talk or write from there.
///
/// A change in Settings > みまもり reaches the app only when it next runs, so the requests already
/// pending keep firing until she opens the app (tapping one of them is enough).
enum DailyCheckInNotifier {
  private static let prefix = "daily-check-in-"

  /// What Settings > みまもり holds now.
  static var settings: DailyCheckInSettings {
    DailyCheckInSettings(reading: { UserDefaults.standard.object(forKey: $0) })
  }

  /// Removes every pending daily request, then adds one per slot (an empty list turns them off).
  /// The identifier is the day, so adding the same day twice replaces it.
  static func replace(with slots: [DateComponents]) async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests().map(\.identifier).filter {
      $0.hasPrefix(prefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: pending)
    for slot in slots {
      let request = UNNotificationRequest(
        identifier: identifier(for: slot), content: content(),
        trigger: UNCalendarNotificationTrigger(dateMatching: slot, repeats: false))
      // Not allowed to notify (she said no): nothing to show her; the chat is still there.
      try? await center.add(request)
    }
  }

  #if DEBUG
    /// `-mimamori-checkin-after-seconds <n>`: one prompt n seconds from now, so the simulator can show
    /// it and the tap into the chat without waiting for 18:00. Its identifier is outside the prefix,
    /// so `replace` leaves it alone.
    static func postSoon(after seconds: TimeInterval) async {
      let request = UNNotificationRequest(
        identifier: "debug-daily-check-in", content: content(),
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false))
      try? await UNUserNotificationCenter.current().add(request)
    }
  #endif

  private static func content() -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.body = DailyCheckIn.prompt
    content.sound = .default
    content.threadIdentifier = "daily-check-in"
    return content
  }

  private static func identifier(for slot: DateComponents) -> String {
    let day = [slot.year, slot.month, slot.day].map { String($0 ?? 0) }.joined(separator: "-")
    return prefix + day
  }
}
