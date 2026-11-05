import SwiftUI
import UserNotifications

@main
struct MimamoriApp: App {
  @UIApplicationDelegateAdaptor private var delegate: AppDelegate
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(delegate.model)
        .task { await delegate.model.requestPushIfJoined() }
        // Launched in the background before the first unlock, the Keychain read as empty; look again.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
          delegate.model.refresh()
        }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        delegate.model.refresh()
        delegate.model.cameToFront()
        Task { await delegate.model.loadCases() }
      }
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  let model = AppModel.live()

  func application(
    _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  /// A case notice or a family reply arrived while the app is open: show it and reload the cases,
  /// so the card or the mother's screen changes at once (and a reply is read aloud).
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    await model.loadCases()
    return [.banner, .list, .sound]
  }

  /// A tap on any of them opens the app on its home screen. For the daily prompt and the call
  /// follow-up that is her chat, where she can answer by talking or writing.
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    await model.loadCases()
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task { await model.didReceiveAPNs(token: deviceToken) }
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
    // Simulators and unsigned builds land here; nothing to show the person.
  }
}
