import Foundation
import Testing

@testable import MimamoriCore

/// A transport that always fails, as with no network.
private struct FailingTransport: HTTPTransport {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    throw URLError(.notConnectedToInternet)
  }
}

@Suite("Safari の拡張のページの問い合わせ")
struct PageCheckTests {
  private let mother = Credentials(
    deviceKey: "dk_test_page", memberId: "m-2", familyId: "f-1", role: .protected
  )

  private func message(url: Any = "https://support-alert.example/warn", text: Any = "ページの文")
    -> [String: Any]
  {
    ["type": "page", "url": url, "text": text]
  }

  @Test("裏側の段階が1なら開かないで、2なら確かめるまで待っての警告を出す")
  func warnings() {
    #expect(
      PageCheck.warning(statusCode: 200, data: Data(#"{"level":1,"reasons":[]}"#.utf8))
        == .doNotOpen)
    #expect(
      PageCheck.warning(statusCode: 200, data: Data(#"{"level":2,"reasons":["x"]}"#.utf8))
        == .waitForFamily)
  }

  @Test(
    "それ以外は警告を出さない(安全という意味ではない)",
    arguments: [
      #"{"level":null,"reasons":[]}"#,
      #"{"level":3}"#,
      #"{"level":"1"}"#,
      #"{"level":0}"#,
      #"{"level":true}"#,
      #"{"level":1.5}"#,
      #"{}"#,
      "[]",
      "not json",
      "",
    ]
  )
  func noWarning(body: String) {
    #expect(PageCheck.warning(statusCode: 200, data: Data(body.utf8)) == nil)
  }

  @Test("200 番台でない答えでは警告を出さない", arguments: [nil, 0, 400, 401, 404, 500])
  func badStatus(status: Int?) {
    #expect(PageCheck.warning(statusCode: status, data: Data(#"{"level":1}"#.utf8)) == nil)
  }

  @Test("拡張の JavaScript への返事は段階の数だけで、警告の無いときは空")
  func reply() {
    #expect(
      PageCheck.reply(for: .answered(.doNotOpen)) as NSDictionary == ["checked": true, "level": 1] as NSDictionary
    )
    #expect(
      PageCheck.reply(for: .answered(.waitForFamily)) as NSDictionary
        == ["checked": true, "level": 2] as NSDictionary
    )
    #expect(PageCheck.reply(for: .answered(nil)) as NSDictionary == ["checked": true] as NSDictionary)
    // A failure is not an answer, so the background script does not remember it for the URL.
    #expect(PageCheck.reply(for: .failed).isEmpty)
  }

  @Test("届いた答えと、届かなかった問い合わせを分ける")
  func outcome() {
    #expect(PageCheck.outcome(statusCode: 200, data: Data(#"{"level":1,"reasons":[]}"#.utf8)) == .answered(.doNotOpen))
    #expect(PageCheck.outcome(statusCode: 200, data: Data(#"{"level":null,"reasons":[]}"#.utf8)) == .answered(nil))
    #expect(PageCheck.outcome(statusCode: 200, data: Data("not json".utf8)) == .failed)
    #expect(PageCheck.outcome(statusCode: 500, data: Data(#"{"level":1}"#.utf8)) == .failed)
    #expect(PageCheck.outcome(statusCode: nil, data: nil) == .failed)
  }

  @Test("端末の鍵をつけて URL とページの文を POST /page に送る")
  func request() throws {
    let request = try #require(
      PageCheck.request(baseURL: testBaseURL, deviceKey: "dk_x", message: message())
    )
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://api.test.invalid/page")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_x")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try bodyJSON(request)
    #expect(body["url"] as? String == "https://support-alert.example/warn")
    #expect(body["text"] as? String == "ページの文")
    #expect(request.timeoutInterval <= PageCheck.timeout)
  }

  @Test("パスワードかカード番号の欄があったかを true か false だけで送る(#137)")
  func secretField() throws {
    var withField = message()
    withField["hasSecretField"] = true
    let sent = try #require(
      PageCheck.request(baseURL: testBaseURL, deviceKey: "dk_x", message: withField)
    )
    let raw = String(decoding: try #require(sent.httpBody), as: UTF8.self)
    #expect(raw.contains(#""hasSecretField":true"#))

    // Absent, or anything other than a boolean from the script, is false: the server only takes a boolean.
    for value: Any? in [nil, "yes"] {
      var other = message()
      other["hasSecretField"] = value
      let request = try #require(
        PageCheck.request(baseURL: testBaseURL, deviceKey: "dk_x", message: other)
      )
      let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
      #expect(body.contains(#""hasSecretField":false"#))
    }
  }

  @Test("ページの文は先頭の5,000字だけを送る(絵文字も1字に数え、途中で割らない)")
  func cutsText() throws {
    let long = "警告" + String(repeating: "😀", count: 6000)
    let request = try #require(
      PageCheck.request(baseURL: testBaseURL, deviceKey: "dk_x", message: message(text: long))
    )
    let text = try #require(try bodyJSON(request)["text"] as? String)
    #expect(text.unicodeScalars.count == PageCheck.textMaxCharacters)
    #expect(text.hasPrefix("警告😀"))
  }

  /// Messages the extension must not send on: other schemes, and shapes it never sends.
  nonisolated(unsafe) private static let refused: [[String: Any]] = [
    ["type": "page", "url": "file:///etc/hosts", "text": ""],
    ["type": "page", "url": "about:blank", "text": ""],
    ["type": "page", "url": "javascript:void(0)", "text": ""],
    ["type": "page", "url": 1, "text": ""],
    ["type": "page", "text": "x"],
    ["type": "other", "url": "https://example.com/", "text": ""],
    ["type": "page", "url": "https://example.com/", "text": 3],
  ]

  @Test("http と https のほかのページや、形の違う知らせは送らない", arguments: 0..<7)
  func refusesOthers(index: Int) {
    #expect(Self.refused.count == 7)
    #expect(PageCheck.request(baseURL: testBaseURL, deviceKey: "dk_x", message: Self.refused[index]) == nil)
  }

  @Test("文の無いページも URL だけで問い合わせる")
  func urlOnly() throws {
    let request = try #require(
      PageCheck.request(
        baseURL: testBaseURL, deviceKey: "dk_x",
        message: ["type": "page", "url": "https://a.example/"]
      )
    )
    #expect(try bodyJSON(request)["text"] as? String == "")
  }

  @Test("問い合わせから警告まで。裏側の1で開かないでを返す")
  func checkRoundTrip() async throws {
    let transport = StubTransport(status: 200, body: #"{"level":1,"reasons":["ウイルスの偽の警告"]}"#)
    let checker = PageChecker(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(mother)
    )
    #expect(await checker.check(message()) == .answered(.doNotOpen))
    #expect(transport.requests.count == 1)
    #expect(
      transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_page")
  }

  @Test("家族に入っていない端末では問い合わせない")
  func notJoined() async {
    let transport = StubTransport(status: 200, body: #"{"level":1}"#)
    let checker = PageChecker(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore())
    #expect(await checker.check(message()) == .failed)
    #expect(transport.requests.isEmpty)
  }

  @Test("401 でも鍵を消さない。消すのはアプリの役目")
  func unauthorizedKeepsKey() async {
    let store = InMemoryDeviceKeyStore(mother)
    let checker = PageChecker(
      baseURL: testBaseURL, transport: StubTransport(status: 401, body: "{}"), store: store
    )
    #expect(await checker.check(message()) == .failed)
    #expect(store.load() == mother)
  }

  @Test("つながらないときは警告を出さずに終える")
  func offline() async {
    let checker = PageChecker(
      baseURL: testBaseURL, transport: FailingTransport(), store: InMemoryDeviceKeyStore(mother)
    )
    #expect(await checker.check(message()) == .failed)
  }
}
