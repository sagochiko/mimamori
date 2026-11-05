import Foundation
import MimamoriCore
import UserNotifications

/// The local notification "さっきの電話、大丈夫だった？". `CallFollowUp` in Core decides whether and
/// when; this only posts it. The end of a call comes from `CallEndWatcher`, which hears it only while
/// the app is in front (#25); the daily prompt (`DailyCheckInNotifier`) covers the rest.
enum CallFollowUpNotifier {
  static func post() async {
    let content = UNMutableNotificationContent()
    content.body = CallFollowUp.prompt
    content.sound = .default
    content.threadIdentifier = "call-follow-up"
    let request = UNNotificationRequest(
      identifier: "call-follow-up", content: content, trigger: nil)
    do {
      try await UNUserNotificationCenter.current().add(request)
    } catch {
      // The prompt still waits on her screen for the next time she opens the app.
    }
  }
}

/// What `CallFollowUp` remembers, kept on this device.
struct UserDefaultsCallFollowUpStore: CallFollowUpStore {
  private let key = "mimamori.callFollowUp"

  func load() -> CallFollowUpState {
    guard let data = UserDefaults.standard.data(forKey: key),
      let state = try? JSONDecoder().decode(CallFollowUpState.self, from: data)
    else { return CallFollowUpState() }
    return state
  }

  func save(_ state: CallFollowUpState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }
}
