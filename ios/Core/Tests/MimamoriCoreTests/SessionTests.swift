import Foundation
import Testing

@testable import MimamoriCore

/// A fresh UserDefaults per test, standing in for the app's own (deleted with the app).
func freshDefaults(installed: Bool) -> UserDefaults {
  let defaults = UserDefaults(suiteName: "mimamori-test-\(UUID().uuidString)")!
  if installed { InstallMarker.mark(defaults) }
  return defaults
}

@MainActor
@Suite("Session: 画面の行き先")
struct SessionTests {
  private func session(
    _ transport: StubTransport, store: InMemoryDeviceKeyStore = InMemoryDeviceKeyStore(.sample)
  ) -> (Session, RouteLog) {
    let log = RouteLog()
    let session = Session(
      baseURL: testBaseURL, transport: transport, store: store, defaults: freshDefaults(installed: true))
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

@Suite("入れ直したときの鍵")
struct InstallMarkerTests {
  @Test("入れ直した直後(印が無い)は、キーチェーンに残った鍵を消して役の選択から始める")
  @MainActor
  func reinstallClearsKeychain() {
    let store = InMemoryDeviceKeyStore(.sample)
    let defaults = freshDefaults(installed: false)

    let session = Session(baseURL: testBaseURL, transport: StubTransport(status: 200), store: store, defaults: defaults)

    #expect(store.load() == nil)
    #expect(session.route == .chooseRole)
    #expect(InstallMarker.isMarked(defaults))
  }

  @Test("2回目からの起動では、鍵を残す")
  @MainActor
  func laterLaunchKeepsKey() {
    let store = InMemoryDeviceKeyStore(.sample)
    let defaults = freshDefaults(installed: false)
    _ = Session(baseURL: testBaseURL, transport: StubTransport(status: 200), store: store, defaults: defaults)
    try? store.save(.sample)

    let session = Session(baseURL: testBaseURL, transport: StubTransport(status: 200), store: store, defaults: defaults)

    #expect(store.load() == .sample)
    #expect(session.route == .familyHome)
  }
}
