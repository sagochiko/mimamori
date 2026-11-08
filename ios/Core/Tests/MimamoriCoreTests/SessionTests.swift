import Foundation
import Testing

@testable import MimamoriCore

@MainActor
@Suite("Session: 画面の行き先")
struct SessionTests {
  private func session(
    _ transport: StubTransport, store: InMemoryDeviceKeyStore = InMemoryDeviceKeyStore(.sample)
  ) -> (Session, RouteLog) {
    let log = RouteLog()
    let session = Session(
      baseURL: testBaseURL, transport: transport, store: store, marker: InMemoryInstallMarker(marked: true))
    session.onRouteChange = { log.routes.append($0) }
    return (session, log)
  }

  @Test("招待のコードを出すときに 401 が返ると、役の選択に戻る")
  func unauthorizedInviteGoesToRoleSelection() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(StubTransport(status: 401), store: store)
    #expect(session.route == .familyHome)

    await #expect(throws: APIError.unauthorized) { _ = try await session.createInvite() }

    #expect(session.route == .chooseRole)
    #expect(log.routes == [.chooseRole])
    #expect(store.load() == nil)
  }

  @Test("APNs の登録で 401 が返っても、役の選択に戻る")
  func unauthorizedAPNsGoesToRoleSelection() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(StubTransport(status: 401), store: store)

    await #expect(throws: APIError.unauthorized) {
      try await session.registerAPNs(token: Data([1, 2]), environment: .sandbox)
    }

    #expect(session.route == .chooseRole)
    #expect(log.routes == [.chooseRole])
    #expect(store.load() == nil)
  }

  @Test("401 以外の失敗では、今の画面のまま")
  func otherFailuresKeepRoute() async throws {
    let (session, log) = session(StubTransport(status: 500))

    await #expect(throws: APIError.http(status: 500)) { _ = try await session.createInvite() }

    #expect(session.route == .familyHome)
    #expect(log.routes.isEmpty)
  }

  @Test("招待のコードで入ると、見守られる人の画面に移る")
  func joinMovesToProtectedHome() async throws {
    let transport = StubTransport(
      status: 201, body: #"{"familyId":"f-1","memberId":"m-2","deviceKey":"dk","role":"protected"}"#)
    let (session, log) = session(transport, store: InMemoryDeviceKeyStore())
    #expect(session.route == .chooseRole)

    _ = try await session.join(code: InviteCode("246810")!, role: .protected, displayName: "見守られる人")

    #expect(session.route == .protectedHome)
    #expect(log.routes == [.protectedHome])
  }

  @Test("家族を作ると、家族の画面に移る")
  func createFamilyMovesToFamilyHome() async throws {
    let transport = StubTransport(
      status: 201,
      body: #"{"familyId":"f-1","memberId":"m-1","deviceKey":"dk","familyToken":"ft","role":"family"}"#)
    let (session, _) = session(transport, store: InMemoryDeviceKeyStore())

    _ = try await session.createFamily(displayName: "作者")

    #expect(session.route == .familyHome)
  }
}

@MainActor
final class RouteLog {
  var routes: [AppRoute] = []
}

/// Before the first unlock after a reboot, the Keychain item (AfterFirstUnlockThisDeviceOnly) reads
/// as nothing. This store hides its content while `device.locked` is true, like that.
final class LockableStore: DeviceKeyStore, @unchecked Sendable {
  let inner: InMemoryDeviceKeyStore
  let device: Device
  init(_ credentials: Credentials?, device: Device) {
    inner = InMemoryDeviceKeyStore(credentials)
    self.device = device
  }
  func load() -> Credentials? { device.locked ? nil : inner.load() }
  func save(_ credentials: Credentials) throws { try inner.save(credentials) }
  func clear() { inner.clear() }
}

final class Device: @unchecked Sendable {
  var locked: Bool
  init(locked: Bool) { self.locked = locked }
}

@MainActor
@Suite("入れ直したときの鍵")
struct InstallMarkerTests {
  private func session(store: any DeviceKeyStore, marker: any InstallMarkerStore, device: Device = Device(locked: false))
    -> Session
  {
    Session(
      baseURL: testBaseURL, transport: StubTransport(status: 200), store: store, marker: marker,
      isProtectedDataAvailable: { !device.locked })
  }

  @Test("入れ直した直後(印が無い)は、キーチェーンに残った鍵を消して役の選択から始める")
  func reinstallClearsKeychain() {
    let store = InMemoryDeviceKeyStore(.sample)
    let marker = InMemoryInstallMarker(marked: false)

    let session = session(store: store, marker: marker)

    #expect(store.load() == nil)
    #expect(session.route == .chooseRole)
    #expect(marker.isMarked)
  }

  @Test("2回目からの起動では、鍵を残す")
  func laterLaunchKeepsKey() {
    let store = InMemoryDeviceKeyStore(.sample)
    let marker = InMemoryInstallMarker(marked: true)

    let session = session(store: store, marker: marker)

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
  }

  @Test("印を書けないとき(空き容量が無いなど)は鍵を消さず、次の機会にまた確かめる")
  func unwritableMarkerKeepsKey() {
    let store = InMemoryDeviceKeyStore(.sample)
    let marker = UnwritableInstallMarker()

    let session = session(store: store, marker: marker)

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
    #expect(marker.attempts == 1)

    session.refresh()

    #expect(store.load() == .sample)
    #expect(marker.attempts == 2)
  }

  @Test("再起動のあと、最初の解除の前に裏で起きても、鍵を消さない")
  func lockedLaunchDoesNotClear() {
    let device = Device(locked: true)
    let store = LockableStore(.sample, device: device)
    // While locked, a marker kept in protected storage would read as missing too.
    let marker = InMemoryInstallMarker(marked: false)

    let session = session(store: store, marker: marker, device: device)

    #expect(store.inner.load() == .sample)
    #expect(!marker.isMarked)
    #expect(session.route == .chooseRole)  // nothing readable yet

    device.locked = false
    marker.markedOnDisk = true  // the real marker was there all along
    session.refresh()

    #expect(store.inner.load() == .sample)
    #expect(session.route == .familyHome)
  }

  @Test("解除の前に起きた入れ直しは、解除したあとの refresh で鍵を消す")
  func lockedReinstallClearsAfterUnlock() {
    let device = Device(locked: true)
    let store = LockableStore(.sample, device: device)
    let marker = InMemoryInstallMarker(marked: false)
    let session = session(store: store, marker: marker, device: device)
    #expect(store.inner.load() == .sample)

    device.locked = false
    session.refresh()

    #expect(store.inner.load() == nil)
    #expect(marker.isMarked)
    #expect(session.route == .chooseRole)
  }

  @Test("refresh は鍵を読み直し、変わったときだけ知らせる")
  func refreshRereadsRoute() {
    let device = Device(locked: true)
    let store = LockableStore(.sample, device: device)
    let session = session(store: store, marker: InMemoryInstallMarker(marked: true), device: device)
    let log = RouteLog()
    session.onRouteChange = { log.routes.append($0) }
    #expect(session.route == .chooseRole)

    device.locked = false
    session.refresh()
    session.refresh()

    #expect(session.route == .familyHome)
    #expect(log.routes == [.familyHome])
  }
}

@Suite("印のファイル")
struct FileInstallMarkerTests {
  @Test("ファイルが無ければ印は無く、付けるとフォルダごと作る")
  func createsFile() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mimamori-marker-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let marker = FileInstallMarker(url: dir.appending(path: "nested/installed"))

    #expect(!marker.isMarked)
    #expect(marker.mark())
    #expect(marker.isMarked)
    #expect(FileManager.default.fileExists(atPath: dir.appending(path: "nested/installed").path))
  }

  @Test("書けない場所では失敗を返す")
  func reportsFailure() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "mimamori-marker-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    // A plain file where the folder should be: the folder cannot be created.
    FileManager.default.createFile(atPath: dir.path, contents: Data())
    let marker = FileInstallMarker(url: dir.appending(path: "installed"))

    #expect(!marker.mark())
    #expect(!marker.isMarked)
  }
}

@MainActor
@Suite("すべて消す")
struct DeleteEverythingTests {
  private func session(_ transport: any HTTPTransport, store: InMemoryDeviceKeyStore) -> (Session, RouteLog) {
    let log = RouteLog()
    let session = Session(
      baseURL: testBaseURL, transport: transport, store: store, marker: InMemoryInstallMarker(marked: true))
    session.onRouteChange = { log.routes.append($0) }
    return (session, log)
  }

  @Test("消せたら、端末の鍵を消して役の選択に戻る")
  func successClearsKeyAndGoesToRoleSelection() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: 204, body: "")
    let (session, log) = session(transport, store: store)
    #expect(session.route == .familyHome)

    try await session.deleteEverything()

    let request = try #require(transport.requests.first)
    #expect(transport.requests.count == 1)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path == "/families/me")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(store.load() == nil)
    #expect(session.route == .chooseRole)
    #expect(log.routes == [.chooseRole])
  }

  @Test("裏側が外の分を消せなかった(502)ときは、鍵を残して今の画面のまま")
  func cleanupFailedKeepsEverything() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: 502, body: #"{"error":"cleanup_failed","pending":["gmail"]}"#)
    let (session, log) = session(transport, store: store)

    await #expect(throws: APIError.http(status: 502)) { try await session.deleteEverything() }

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
    #expect(log.routes.isEmpty)
  }

  @Test("つながらないときも、鍵を残して今の画面のまま")
  func offlineKeepsEverything() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(OfflineTransport(), store: store)

    await #expect(throws: URLError.self) { try await session.deleteEverything() }

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
    #expect(log.routes.isEmpty)
  }

  @Test("鍵がもう効かない(401)ときは、鍵を消して役の選択に戻る")
  func unauthorizedGoesToRoleSelection() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(StubTransport(status: 401), store: store)

    await #expect(throws: APIError.unauthorized) { try await session.deleteEverything() }

    #expect(store.load() == nil)
    #expect(session.route == .chooseRole)
    #expect(log.routes == [.chooseRole])
  }

  @Test("家族に入っていなければ、何も送らない")
  func notJoinedSendsNothing() async throws {
    let transport = StubTransport(status: 204, body: "")
    let (session, _) = session(transport, store: InMemoryDeviceKeyStore())

    await #expect(throws: APIError.notJoined) { try await session.deleteEverything() }

    #expect(transport.requests.isEmpty)
  }
}

@MainActor
@Suite("この iPhone を外す")
struct LeaveFamilyTests {
  private func session(_ transport: any HTTPTransport, store: InMemoryDeviceKeyStore) -> (Session, RouteLog) {
    let log = RouteLog()
    let session = Session(
      baseURL: testBaseURL, transport: transport, store: store, marker: InMemoryInstallMarker(marked: true))
    session.onRouteChange = { log.routes.append($0) }
    return (session, log)
  }

  @Test("DELETE /members/me だけを送り、外せたら端末の鍵を消して役の選択に戻る(家族は消さない)")
  func successClearsKeyAndGoesToRoleSelection() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: 204, body: "")
    let (session, log) = session(transport, store: store)
    #expect(session.route == .familyHome)

    try await session.leaveFamily()

    let request = try #require(transport.requests.first)
    #expect(transport.requests.count == 1)
    #expect(request.httpMethod == "DELETE")
    #expect(request.url?.path == "/members/me")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(store.load() == nil)
    #expect(session.route == .chooseRole)
    #expect(log.routes == [.chooseRole])
  }

  @Test("裏側が断った(500)ときは、鍵を残して今の画面のまま")
  func serverErrorKeepsKey() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(StubTransport(status: 500, body: #"{"error":"internal"}"#), store: store)

    await #expect(throws: APIError.http(status: 500)) { try await session.leaveFamily() }

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
    #expect(log.routes.isEmpty)
  }

  @Test("つながらないときも、鍵を残して今の画面のまま")
  func offlineKeepsKey() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(OfflineTransport(), store: store)

    await #expect(throws: URLError.self) { try await session.leaveFamily() }

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
    #expect(log.routes.isEmpty)
  }

  @Test("鍵がもう効かない(401)ときは、鍵を消して役の選択に戻る")
  func unauthorizedGoesToRoleSelection() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let (session, log) = session(StubTransport(status: 401), store: store)

    await #expect(throws: APIError.unauthorized) { try await session.leaveFamily() }

    #expect(store.load() == nil)
    #expect(session.route == .chooseRole)
    #expect(log.routes == [.chooseRole])
  }

  @Test("家族に入っていなければ、何も送らない")
  func notJoinedSendsNothing() async throws {
    let transport = StubTransport(status: 204, body: "")
    let (session, _) = session(transport, store: InMemoryDeviceKeyStore())

    await #expect(throws: APIError.notJoined) { try await session.leaveFamily() }

    #expect(transport.requests.isEmpty)
  }
}

/// A transport with no network, as in airplane mode.
struct OfflineTransport: HTTPTransport {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    throw URLError(.notConnectedToInternet)
  }
}
