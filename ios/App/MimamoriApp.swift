import SwiftUI

@main
struct MimamoriApp: App {
  @UIApplicationDelegateAdaptor private var delegate: AppDelegate

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(delegate.model)
        .task { await delegate.model.requestPushIfJoined() }
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
