import Foundation
import Testing

@testable import MimamoriCore

@Suite("APIClient")
struct APIClientTests {
  // MARK: 端末の鍵を付ける

  @Test("鍵のある呼び出しに Authorization: Bearer <deviceKey> を付ける")
  func addsBearer() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(
      status: 201, body: #"{"code":"123456","expiresAt":"2026-11-04T03:00:00Z"}"#)
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    _ = try await client.createInvite()

    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://api.test.invalid/invites")
  }

  @Test("APNs の登録も鍵を付けて PUT /members/me/apns に送る")
  func registerAPNsSendsBearer() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: 204, body: "")
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    try await client.registerAPNs(token: Data([0x0a, 0xff, 0x01]), environment: .sandbox)

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/members/me/apns")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    let body = try bodyJSON(request)
    #expect(body["token"] as? String == "0aff01")
    #expect(body["env"] as? String == "sandbox")
  }

  @Test("本番の APNs は env を production で送る(省くと裏側も production とみなす)")
  func registerAPNsProduction() async throws {
    let transport = StubTransport(status: 204, body: "")
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))

    try await client.registerAPNs(token: Data([0x00, 0x10]), environment: .production)

    let body = try bodyJSON(try #require(transport.requests.first))
    #expect(body["token"] as? String == "0010")
    #expect(body["env"] as? String == "production")
  }

  @Test("使い終わった、期限切れ、知らないコードは 404 で、鍵はしまわない")
  func joinWithBadCode() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(status: 404, body: #"{"error":"not_found"}"#)
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    await #expect(throws: APIError.http(status: 404)) {
      _ = try await client.join(code: InviteCode("999999")!, role: .protected, displayName: "見守られる人")
    }
    #expect(store.load() == nil)
    #expect(AppRoute(store.load()) == .chooseRole)
  }

  @Test("鍵が無ければ、鍵の要る呼び出しは送らずに止める")
  func missingKeyDoesNotSend() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(status: 201)
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    await #expect(throws: APIError.notJoined) {
      _ = try await client.createInvite()
    }
    #expect(transport.requests.isEmpty)
  }

  @Test("入る前の呼び出し(招待のコードで入る)には Authorization を付けない")
  func joinHasNoBearer() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"familyId":"f-1","memberId":"m-2","deviceKey":"dk_new","role":"protected"}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let code = try #require(InviteCode("246810"))
    _ = try await client.join(code: code, role: .protected, displayName: "見守られる人")

    let request = try #require(transport.requests.first)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.url?.path == "/invites/246810/join")
    let body = try bodyJSON(request)
    #expect(body["role"] as? String == "protected")
    #expect(body["display_name"] as? String == "見守られる人")
  }

  // MARK: 返ってきた鍵をしまう

  @Test("招待のコードで入ると、返ってきた deviceKey と役と familyToken をしまう")
  func joinStoresCredentials() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"familyId":"f-1","memberId":"m-2","deviceKey":"dk_new","familyToken":"0123456789abcdef0123456789abcdef","role":"protected"}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let member = try await client.join(
      code: InviteCode("246810")!, role: .protected, displayName: "見守られる人")

    #expect(member == Member(id: "m-2", familyId: "f-1", role: .protected, displayName: "見守られる人"))
    #expect(
      store.load()
        == Credentials(
          deviceKey: "dk_new", memberId: "m-2", familyId: "f-1", role: .protected,
          familyToken: "0123456789abcdef0123456789abcdef"))
    #expect(AppRoute(store.load()) == .protectedHome)
  }

  @Test("家族を作ると、呼んだ端末が家族の役で入り、鍵をしまう")
  func createFamilyStoresCredentials() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"familyId":"f-9","memberId":"m-1","deviceKey":"dk_first","familyToken":"ft_0123456789abcdef0123456789ab","role":"family"}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let member = try await client.createFamily(displayName: "作者")

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/families")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(try bodyJSON(request)["display_name"] as? String == "作者")
    #expect(member == Member(id: "m-1", familyId: "f-9", role: .family, displayName: "作者"))
    #expect(store.load()?.deviceKey == "dk_first")
    // Kept for the SMS and DNS endpoints (`/sms/<familyToken>`), which later tasks hand to the extensions.
    #expect(store.load()?.familyToken == "ft_0123456789abcdef0123456789ab")
    #expect(AppRoute(store.load()) == .familyHome)
  }

  @Test("snake_case で返ってきても読める(裏側の書き方の揺れに備える)")
  func decodesSnakeCase() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"family_id":"f-1","member_id":"m-3","device_key":"dk_s","role":"family"}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let member = try await client.join(code: InviteCode("111111")!, role: .family, displayName: "妹")

    #expect(member == Member(id: "m-3", familyId: "f-1", role: .family, displayName: "妹"))
    #expect(store.load()?.deviceKey == "dk_s")
  }

  // MARK: 401 で役の選択に戻る

  @Test("401 が返ると deviceKey を消し、onUnauthorized を1回呼ぶ(画面の切り替えは SessionTests)")
  func unauthorizedClearsKey() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: 401, body: #"{"error":"unauthorized"}"#)
    let counter = Counter()
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store) {
      counter.increment()
    }

    await #expect(throws: APIError.unauthorized) {
      _ = try await client.createInvite()
    }

    #expect(store.load() == nil)
    #expect(counter.value == 1)
  }

  @Test("401 以外の失敗では deviceKey を消さない", arguments: [400, 403, 404, 410, 429, 500, 503])
  func otherErrorsKeepKey(status: Int) async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: status)
    let counter = Counter()
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store) {
      counter.increment()
    }

    await #expect(throws: APIError.http(status: status)) {
      _ = try await client.createInvite()
    }

    #expect(store.load() == .sample)
    #expect(counter.value == 0)
  }

  @Test("通信そのものの失敗でも deviceKey を消さない")
  func transportFailureKeepsKey() async throws {
    struct Offline: Error {}
    struct FailingTransport: HTTPTransport {
      func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw Offline() }
    }
    let store = InMemoryDeviceKeyStore(.sample)
    let client = APIClient(baseURL: testBaseURL, transport: FailingTransport(), store: store)

    await #expect(throws: Offline.self) {
      _ = try await client.createInvite()
    }
    #expect(store.load() == .sample)
  }

  @Test("招待のコードは数字と期限を読む")
  func decodesInvite() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(
      status: 201, body: #"{"code":"135790","expiresAt":"2026-11-04T03:00:00Z"}"#)
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let invite = try await client.createInvite()

    #expect(invite.code.value == "135790")
    #expect(invite.expiresAt == ISO8601DateFormatter().date(from: "2026-11-04T03:00:00Z"))
  }

  @Test("6桁でないコードが返ってきたら受け取らない")
  func rejectsMalformedInviteFromServer() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(
      status: 201, body: #"{"code":"12345","expiresAt":"2026-11-04T03:00:00Z"}"#)
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    await #expect(throws: APIError.self) {
      _ = try await client.createInvite()
    }
  }
}
