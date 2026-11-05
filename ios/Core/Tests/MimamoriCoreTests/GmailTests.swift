import Foundation
import Testing

@testable import MimamoriCore

@Suite("Gmail の許可")
struct GmailTests {
  private func client(_ transport: StubTransport) -> APIClient {
    APIClient(baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
  }

  @Test("GET /gmail/connect で同意の画面の URL と今の許可の時刻を読む")
  func connect() async throws {
    let transport = StubTransport(
      status: 200,
      body:
        #"{"url":"https://accounts.google.com/o/oauth2/v2/auth?state=abc","grantedAt":"2026-11-05T00:00:00.000Z"}"#
    )
    let grant = try await client(transport).gmailConnect()

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/gmail/connect")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(grant?.url.absoluteString == "https://accounts.google.com/o/oauth2/v2/auth?state=abc")
    #expect(grant?.grantedAt == Date(timeIntervalSince1970: 1_793_836_800))
  }

  @Test("許可が無ければ grantedAt は nil")
  func connectWithoutGrant() async throws {
    let transport = StubTransport(
      status: 200, body: #"{"url":"https://accounts.google.com/o/oauth2/v2/auth","grantedAt":null}"#
    )
    let grant = try await client(transport).gmailConnect()
    #expect(grant != nil)
    #expect(grant?.grantedAt == nil)
  }

  @Test("裏側に Google の設定が無い(503)ときは nil で、ボタンを出さない")
  func notConfigured() async throws {
    let transport = StubTransport(status: 503, body: #"{"error":"gmail_not_configured"}"#)
    #expect(try await client(transport).gmailConnect() == nil)
  }

  @Test("家族の役には 403 が返り、エラーになる")
  func familyRole() async throws {
    let transport = StubTransport(status: 403, body: #"{"error":"protected_only"}"#)
    await #expect(throws: APIError.http(status: 403)) { try await client(transport).gmailConnect() }
  }

  @Test("許可が無いか、許可から6日を過ぎたらボタンを出す")
  func needsGrant() {
    let now = Date(timeIntervalSince1970: 1_793_836_800)
    let day: TimeInterval = 24 * 3600
    let url = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    #expect(GmailGrant(url: url, grantedAt: nil).needsGrant(now: now))
    #expect(!GmailGrant(url: url, grantedAt: now - 5 * day).needsGrant(now: now))
    #expect(!GmailGrant(url: url, grantedAt: now - 6 * day + 60).needsGrant(now: now))
    #expect(GmailGrant(url: url, grantedAt: now - 6 * day).needsGrant(now: now))
    #expect(GmailGrant(url: url, grantedAt: now - 8 * day).needsGrant(now: now))
  }

  @Test("Google から戻った URL の結果を読む")
  func result() {
    #expect(
      GmailConnectResult(callback: URL(string: "mimamori://gmail?result=connected")!) == .connected)
    #expect(GmailConnectResult(callback: URL(string: "mimamori://gmail?result=denied")!) == .denied)
    #expect(GmailConnectResult(callback: URL(string: "mimamori://gmail?result=failed")!) == .failed)
    #expect(GmailConnectResult(callback: URL(string: "mimamori://gmail")!) == .failed)
    // Another scheme or host is not ours.
    #expect(
      GmailConnectResult(callback: URL(string: "https://example.com/gmail?result=connected")!)
        == .failed)
    #expect(
      GmailConnectResult(callback: URL(string: "mimamori://other?result=connected")!) == .failed)
  }
}
