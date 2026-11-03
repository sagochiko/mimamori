import Foundation
import MimamoriCore
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel {
  enum Problem: Equatable {
    /// The code was not accepted (wrong, used, or older than 24 hours).
    case badCode
    /// Anything else: offline, server down.
    case unreachable
  }

  private(set) var route: AppRoute
  private(set) var invite: Invite?
  private(set) var isBusy = false
  var problem: Problem?

  @ObservationIgnored private let store: any DeviceKeyStore
  @ObservationIgnored private let client: APIClient

  init(
    store: any DeviceKeyStore = KeychainDeviceKeyStore(),
    transport: any HTTPTransport = URLSessionTransport(),
    baseURL: URL = AppConfig.apiBaseURL
  ) {
    self.store = store
    self.client = APIClient(baseURL: baseURL, transport: transport, store: store)
    self.route = AppRoute(store.load())
  }

  /// The model the app runs with. Debug builds launched with `-mimamori-stub` use canned answers.
  static func live() -> AppModel {
    #if DEBUG
      if ScreenshotStubTransport.isRequested {
        return AppModel(store: InMemoryDeviceKeyStore(), transport: ScreenshotStubTransport())
      }
    #endif
    return AppModel()
  }

  func createFamily(displayName: String) async {
    await run { try await $0.createFamily(displayName: displayName) }
    afterJoin()
  }

  func join(code: InviteCode, role: Role, displayName: String) async {
    await run(codeCall: true) { try await $0.join(code: code, role: role, displayName: displayName) }
    afterJoin()
  }

  func createInvite() async {
    await run { [weak self] client in
      let invite = try await client.createInvite()
      self?.invite = invite
    }
  }

  /// Asks for notification permission once the person has joined, then registers with APNs.
  func requestPushIfJoined() async {
    guard route != .chooseRole else { return }
    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    if granted { UIApplication.shared.registerForRemoteNotifications() }
  }

  func didReceiveAPNs(token: Data) async {
    #if DEBUG
      let environment = APNsEnvironment.sandbox
    #else
      let environment = APNsEnvironment.production
    #endif
    // Quiet on failure: the token is sent again on the next launch.
    try? await client.registerAPNs(token: token, environment: environment)
    syncRoute()
  }

  // MARK: -

  private func afterJoin() {
    syncRoute()
    Task { await requestPushIfJoined() }
  }

  /// The route always follows the Keychain: a 401 clears the key, which brings back role selection.
  private func syncRoute() {
    route = AppRoute(store.load())
    if route == .chooseRole { invite = nil }
  }

  private func run(codeCall: Bool = false, _ body: (APIClient) async throws -> Void) async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await body(client)
      problem = nil
    } catch APIError.unauthorized {
      syncRoute()
    } catch APIError.http(let status) where codeCall && [400, 404, 409, 410].contains(status) {
      problem = .badCode
    } catch {
      problem = .unreachable
    }
  }
}
