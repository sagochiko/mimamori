import SwiftUI

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
      if phase == .active { delegate.model.refresh() }
    }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
  let model = AppModel.live()

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Task { await model.didReceiveAPNs(token: deviceToken) }
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
    // Simulators and unsigned builds land here; nothing to show the person.
  }
}
