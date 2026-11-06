import BackgroundTasks
import Foundation
import MimamoriCore
import UIKit
import UserNotifications

/// The checks the app runs on its own (task 17, #19): free space now, more later. `CheckupPolicy` in
/// Core decides whether and when; this reads the iPhone and posts the notification.
enum CheckupNotifier {
  static let storageIdentifier = "checkup-storage"

  /// Free space as the Settings app counts it for things she would keep (photos, app updates). Read
  /// for the prompt on her screen only (reason 85F4.1 in PrivacyInfo.xcprivacy); it is never sent.
  static func availableBytes() -> Int64? {
    let values = try? URL.homeDirectory.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey
    ])
    return values?.volumeAvailableCapacityForImportantUsage
  }

  static func post(_ text: String) async {
    let content = UNMutableNotificationContent()
    content.body = text
    content.sound = .default
    content.threadIdentifier = storageIdentifier
    let request = UNNotificationRequest(
      identifier: storageIdentifier, content: content, trigger: nil)
    // Not allowed to notify: the prompt still waits on her screen.
    try? await UNUserNotificationCenter.current().add(request)
  }

  static func removeDelivered() {
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [
      storageIdentifier
    ])
  }
}

/// What `CheckupPolicy` remembers, kept on this device. No amounts.
struct UserDefaultsCheckupStore: CheckupStore {
  private let key = "mimamori.checkup"

  func load() -> CheckupState {
    guard let data = UserDefaults.standard.data(forKey: key),
      let state = try? JSONDecoder().decode(CheckupState.self, from: data)
    else { return CheckupState() }
    return state
  }

  func save(_ state: CheckupState) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  func clear() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}

/// `POST /heartbeat` with whether notifications and background refresh are on, a few times a day at
/// most (`HeartbeatGate`).
enum HeartbeatSender {
  private static let key = "mimamori.heartbeatGate"

  @MainActor
  static func report() async -> HeartbeatReport {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    let notifications: Bool =
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: true
      default: false
      }
    return HeartbeatReport(
      notificationsOn: notifications,
      backgroundRefreshOn: UIApplication.shared.backgroundRefreshStatus == .available)
  }

  static func gate() -> HeartbeatGate {
    guard let data = UserDefaults.standard.data(forKey: key),
      let gate = try? JSONDecoder().decode(HeartbeatGate.self, from: data)
    else { return HeartbeatGate() }
    return gate
  }

  static func save(_ gate: HeartbeatGate) {
    guard let data = try? JSONEncoder().encode(gate) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }

  static func forget() {
    UserDefaults.standard.removeObject(forKey: key)
  }
}

/// The background refresh that runs the checks and the heartbeat while she does not open the app.
/// iOS decides when it runs; `earliestBeginDate` is only the soonest.
enum CheckupBackground {
  /// Also in Info.plist's BGTaskSchedulerPermittedIdentifiers (ios/project.yml).
  static let identifier = "com.sagochiko.mimamori.checkup"
  static let every: TimeInterval = 6 * 3600

  /// Must run before the app finishes launching.
  static func register(_ run: @escaping @Sendable () async -> Void) {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
      schedule()
      let finished = Finished(task)
      let work = Task {
        await run()
        finished.done()
      }
      task.expirationHandler = { work.cancel() }
    }
  }

  /// BGTask is not Sendable; iOS allows setTaskCompleted from any thread, and it is called once.
  private final class Finished: @unchecked Sendable {
    private let task: BGTask
    init(_ task: BGTask) { self.task = task }
    func done() { task.setTaskCompleted(success: true) }
  }

  static func schedule() {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: every)
    // Fails on the simulator and when background refresh is off; the next foreground tries again.
    try? BGTaskScheduler.shared.submit(request)
  }

  static func cancel() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }
}
