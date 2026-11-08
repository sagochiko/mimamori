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
    if marker.isMarked {
      installCheckPending = false
      return
    }
    // Write the marker first. If it cannot be written (disk full), clearing now would wipe the key
    // again on every launch, so keep it and try once more next time.
    guard marker.mark() else { return }
    installCheckPending = false
    store.clear()
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

  public func cases() async throws -> [Case] {
    try await call { try await $0.cases() }
  }

  public func resolve(caseId: String) async throws -> Case {
    try await call { try await $0.resolve(caseId: caseId) }
  }

  public func consult(text: String, history: [ConsultTurn] = []) async throws -> ConsultAnswer {
    try await call { try await $0.consult(text: text, history: history) }
  }

  /// A screenshot she picked with the photo button in her chat (#221), with what she wrote if anything.
  /// No earlier turns go with it, as from the share sheet.
  public func consult(image: ConsultImage, text: String = "") async throws -> ConsultAnswer {
    try await call { try await $0.consult(image: image, text: text) }
  }

  public func smiles() async throws -> SmileBoard {
    try await call { try await $0.smiles() }
  }

  @discardableResult
  public func postSmile(photoJPEG: Data? = nil, score: Double? = nil, note: SmileNote? = nil) async throws -> Smile {
    try await call { try await $0.postSmile(photoJPEG: photoJPEG, score: score, note: note) }
  }

  public func smilePhoto(id: String) async throws -> Data {
    try await call { try await $0.smilePhoto(id: id) }
  }

  @discardableResult
  public func setSmileDeadline(hour: Int) async throws -> Int {
    try await call { try await $0.setSmileDeadline(hour: hour) }
  }

  public func memberSettings() async throws -> MemberSettings {
    try await call { try await $0.memberSettings() }
  }

  @discardableResult
  public func setMemberSettings(_ change: MemberSettingsChange) async throws -> MemberSettings {
    try await call { try await $0.setMemberSettings(change) }
  }

  public func gmailConnect() async throws -> GmailGrant? {
    try await call { try await $0.gmailConnect() }
  }

  public func heartbeat(_ report: HeartbeatReport) async throws {
    try await call { try await $0.heartbeat(report) }
  }

  /// "この iPhone を外す". After a 2xx the key is gone, so the route becomes role selection; on failure it stays.
  public func leaveFamily() async throws {
    try await call { try await $0.leaveFamily() }
  }

  /// "家族を削除". After a 2xx the key is gone, so the route becomes role selection; on failure it stays.
  public func deleteEverything() async throws {
    try await call { try await $0.deleteEverything() }
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
  /// Writes the marker. Returns false when it could not be written.
  @discardableResult func mark() -> Bool
}

/// An empty file (the App puts it in Application Support). Its existence can be checked even while
/// the device is locked, and it is deleted with the app.
public struct FileInstallMarker: InstallMarkerStore {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public var isMarked: Bool { FileManager.default.fileExists(atPath: url.path) }

  @discardableResult
  public func mark() -> Bool {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      return false
    }
    return FileManager.default.createFile(atPath: url.path, contents: Data())
  }
}
