import Foundation

/// Decides which screen the app shows and keeps it in step with the stored device key.
/// Every API call of the app goes through here, so a 401 from any of them (including the APNs
/// registration that runs without a screen) brings back role selection.
@MainActor
public final class Session {
  public private(set) var route: AppRoute {
    didSet { if route != oldValue { onRouteChange?(route) } }
  }
  /// Called after `route` changes. The App mirrors it into its observable model.
  public var onRouteChange: ((AppRoute) -> Void)?

  private let client: APIClient
  private let store: any DeviceKeyStore

  /// `defaults` must be storage that is deleted with the app (`UserDefaults.standard`), unlike the
  /// Keychain. A missing install marker means a fresh install, and the old key is dropped.
  public init(
    baseURL: URL,
    transport: any HTTPTransport = URLSessionTransport(),
    store: any DeviceKeyStore,
    defaults: UserDefaults
  ) {
    InstallMarker.clearIfReinstalled(defaults, store: store)
    self.store = store
    self.client = APIClient(baseURL: baseURL, transport: transport, store: store)
    self.route = AppRoute(store.load())
  }

  @discardableResult
  public func createFamily(displayName: String) async throws -> Member {
    try await call { try await $0.createFamily(displayName: displayName) }
  }

  @discardableResult
  public func join(code: InviteCode, role: Role, displayName: String) async throws -> Member {
    try await call { try await $0.join(code: code, role: role, displayName: displayName) }
  }

  public func createInvite() async throws -> Invite {
    try await call { try await $0.createInvite() }
  }

  public func registerAPNs(token: Data, environment: APNsEnvironment) async throws {
    try await call { try await $0.registerAPNs(token: token, environment: environment) }
  }

  /// Runs one call and then follows the Keychain: joining stores a key, a 401 clears it.
  private func call<T>(_ body: (APIClient) async throws -> T) async throws -> T {
    defer { route = AppRoute(store.load()) }
    return try await body(client)
  }
}

/// A flag in storage that goes away with the app. The Keychain item survives deleting the app,
/// so without this a wrong role choice could not be undone even by reinstalling.
public enum InstallMarker {
  static let key = "mimamori.installed"

  public static func isMarked(_ defaults: UserDefaults) -> Bool { defaults.bool(forKey: key) }
  public static func mark(_ defaults: UserDefaults) { defaults.set(true, forKey: key) }

  static func clearIfReinstalled(_ defaults: UserDefaults, store: any DeviceKeyStore) {
    guard !isMarked(defaults) else { return }
    store.clear()
    mark(defaults)
  }
}
