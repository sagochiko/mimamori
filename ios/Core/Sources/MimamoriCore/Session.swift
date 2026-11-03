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
  private let marker: any InstallMarkerStore
  private let isProtectedDataAvailable: () -> Bool
  private var installCheckPending = true

  /// `marker` must live in storage deleted with the app, unlike the Keychain: a missing marker means
  /// a fresh install, and the old key is dropped. Before the first unlock after a reboot the Keychain
  /// reads as empty, so nothing is decided then; call `refresh()` once data is available again.
  public init(
    baseURL: URL,
    transport: any HTTPTransport = URLSessionTransport(),
    store: any DeviceKeyStore,
    marker: any InstallMarkerStore,
    isProtectedDataAvailable: @escaping () -> Bool = { true }
  ) {
    self.store = store
    self.marker = marker
    self.isProtectedDataAvailable = isProtectedDataAvailable
    self.client = APIClient(baseURL: baseURL, transport: transport, store: store)
    self.route = .chooseRole
    checkInstallIfPossible()
    self.route = AppRoute(store.load())
  }

  /// Re-reads the stored key. The App calls it when protected data becomes available and when the
  /// scene becomes active, so a launch before the first unlock does not leave role selection on screen.
  public func refresh() {
    checkInstallIfPossible()
    route = AppRoute(store.load())
  }

  private func checkInstallIfPossible() {
    guard installCheckPending, isProtectedDataAvailable() else { return }
    installCheckPending = false
    guard !marker.isMarked else { return }
    store.clear()
    marker.mark()
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

/// A flag kept where it goes away with the app. The Keychain item survives deleting the app, so
/// without this a wrong role choice could not be undone even by reinstalling.
public protocol InstallMarkerStore: Sendable {
  var isMarked: Bool { get }
  func mark()
}

/// An empty file (the App puts it in Application Support). Its existence can be checked even while
/// the device is locked, and it is deleted with the app.
public struct FileInstallMarker: InstallMarkerStore {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public var isMarked: Bool { FileManager.default.fileExists(atPath: url.path) }

  public func mark() {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data())
  }
}
