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
    #expect(body["apns_token"] as? String == "0aff01")
    #expect(body["apns_env"] as? String == "sandbox")
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
        #"{"deviceKey":"dk_new","member":{"id":"m-2","familyId":"f-1","role":"protected","displayName":"見守られる人"}}"#
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

  @Test("招待のコードで入ると、返ってきた deviceKey と役をしまう")
  func joinStoresCredentials() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"deviceKey":"dk_new","member":{"id":"m-2","familyId":"f-1","role":"protected","displayName":"見守られる人"}}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let member = try await client.join(
      code: InviteCode("246810")!, role: .protected, displayName: "見守られる人")

    #expect(member == Member(id: "m-2", familyId: "f-1", role: .protected, displayName: "見守られる人"))
    #expect(
      store.load()
        == Credentials(deviceKey: "dk_new", memberId: "m-2", familyId: "f-1", role: .protected))
    #expect(AppRoute(store.load()) == .protectedHome)
  }

  @Test("家族を作ると、呼んだ端末が家族の役で入り、鍵をしまう")
  func createFamilyStoresCredentials() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"deviceKey":"dk_first","member":{"id":"m-1","familyId":"f-9","role":"family","displayName":"作者"}}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let member = try await client.createFamily(displayName: "作者")

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/families")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(try bodyJSON(request)["display_name"] as? String == "作者")
    #expect(member.role == .family)
    #expect(store.load()?.deviceKey == "dk_first")
    #expect(AppRoute(store.load()) == .familyHome)
  }

  @Test("snake_case で返ってきても読める(裏側の書き方の揺れに備える)")
  func decodesSnakeCase() async throws {
    let store = InMemoryDeviceKeyStore()
    let transport = StubTransport(
      status: 201,
      body:
        #"{"device_key":"dk_s","member":{"id":"m-3","family_id":"f-1","role":"family","display_name":"妹"}}"#
    )
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store)

    let member = try await client.join(code: InviteCode("111111")!, role: .family, displayName: "妹")

    #expect(member.familyId == "f-1")
    #expect(member.displayName == "妹")
    #expect(store.load()?.deviceKey == "dk_s")
  }

  // MARK: 401 で役の選択に戻る

  @Test("401 が返ると deviceKey を消し、役の選択に戻る")
  func unauthorizedClearsKey() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let transport = StubTransport(status: 401, body: #"{"error":"unauthorized"}"#)
    let counter = Counter()
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: store) {
      counter.increment()
    }
    #expect(AppRoute(store.load()) == .familyHome)

    await #expect(throws: APIError.unauthorized) {
      _ = try await client.createInvite()
    }

    #expect(store.load() == nil)
    #expect(counter.value == 1)
    #expect(AppRoute(store.load()) == .chooseRole)
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
