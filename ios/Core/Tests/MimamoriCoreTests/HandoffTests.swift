import Foundation
import Testing

@testable import MimamoriCore

/// The shape `GET /cases` answers with (server/src/cases.ts, CaseView).
func caseJSON(
  id: String = "c-1",
  state: String = "notified",
  assignee: (id: String, name: String)? = nil,
  notifiedAt: String = "2026-11-03T10:00:00.000Z",
  renotifiedAt: String? = nil,
  aiReply: String? = nil,
  relays: [(id: String, from: String, name: String, body: String, at: String)] = []
) -> String {
  let assigneeJSON =
    assignee.map { #"{"memberId":"\#($0.id)","displayName":"\#($0.name)"}"# } ?? "null"
  let relaysJSON = relays.map {
    #"{"id":"\#($0.id)","fromMemberId":"\#($0.from)","fromName":"\#($0.name)","body":"\#($0.body)","createdAt":"\#($0.at)"}"#
  }.joined(separator: ",")
  return #"""
    {"id":"\#(id)","alertId":"a-1","state":"\#(state)","assigneeMemberId":\#(assignee.map { "\"\($0.id)\"" } ?? "null"),
     "assignee":\#(assigneeJSON),"notifiedAt":"\#(notifiedAt)",
     "acceptedAt":\#(assignee == nil ? "null" : "\"2026-11-03T10:05:00.000Z\""),
     "resolvedAt":\#(state == "resolved" ? "\"2026-11-03T11:00:00.000Z\"" : "null"),
     "renotifiedAt":\#(renotifiedAt.map { "\"\($0)\"" } ?? "null"),
     "alert":{"level":1,"source":"call","summary":"警察を名乗る電話の相談","reasons":["口座の移し替えを求めた"]},
     "aiReply":\#(aiReply.map { "\"\($0)\"" } ?? "null"),
     "relays":[\#(relaysJSON)]}
    """#
}

func decodeCase(_ json: String) throws -> Case {
  try APIClient.decoder.decode(Case.self, from: Data(json.utf8))
}

let tenOClock = try! Date("2026-11-03T10:00:00Z", strategy: .iso8601)

@Suite("相談の形")
struct CaseShapeTests {
  @Test("裏側の相談を読む。受け持ちの名前、知らせの中身、AI の答え、返事が入る")
  func decodesFullCase() throws {
    let item = try decodeCase(
      caseJSON(
        state: "accepted", assignee: ("m-2", "妹"), aiReply: "送金はしないで",
        relays: [("r-1", "m-2", "妹", "今から電話するね", "2026-11-03T10:06:00.000Z")]))
    #expect(item.state == .accepted)
    #expect(item.assignee == CaseMember(memberId: "m-2", displayName: "妹"))
    #expect(item.alert?.level == .doNotOpen)
    #expect(item.alert?.summary == "警察を名乗る電話の相談")
    #expect(item.alert?.reasons == ["口座の移し替えを求めた"])
    #expect(item.aiReply == "送金はしないで")
    #expect(item.relays.map(\.body) == ["今から電話するね"])
    #expect(item.relays.first?.fromName == "妹")
  }

  @Test("新しい欄が無い古い形も読める")
  func decodesOldShape() throws {
    let json = #"""
      {"id":"c-1","alertId":null,"state":"notified","assigneeMemberId":null,
       "notifiedAt":"2026-11-03T00:00:00.123Z","acceptedAt":null,"resolvedAt":null}
      """#
    let item = try decodeCase(json)
    #expect(item.relays.isEmpty)
    #expect(item.alert == nil)
    #expect(item.assignee == nil)
  }
}

@Suite("APIClient: 引き継ぎ")
struct HandoffAPITests {
  private func client(_ transport: StubTransport) -> APIClient {
    APIClient(baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
  }

  @Test("GET /cases を鍵つきで読む")
  func listsCases() async throws {
    let transport = StubTransport(status: 200, body: #"{"cases":[\#(caseJSON())]}"#)
    let cases = try await client(transport).cases()
    #expect(cases.map(\.id) == ["c-1"])
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/cases")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
  }

  @Test("引き受けは POST /cases/{id}/accept")
  func accepts() async throws {
    let transport = StubTransport(
      status: 200, body: caseJSON(state: "accepted", assignee: ("m-1", "作者")))
    let item = try await client(transport).accept(caseId: "c-1")
    #expect(item.state == .accepted)
    #expect(transport.requests.first?.url?.path == "/cases/c-1/accept")
    #expect(transport.requests.first?.httpMethod == "POST")
  }

  @Test("先に誰かが引き受けていたら、409 の受け持ちの名前を返す")
  func acceptTakenReturnsName() async throws {
    let transport = StubTransport(
      status: 409,
      body: #"{"error":"already_accepted","assignee":{"memberId":"m-2","displayName":"妹"}}"#)
    await #expect(throws: APIError.conflict(code: "already_accepted", assigneeName: "妹")) {
      _ = try await client(transport).accept(caseId: "c-1")
    }
  }

  @Test("返事は文字で POST /cases/{id}/relay に送る")
  func relays() async throws {
    let transport = StubTransport(
      status: 201, body: #"{"id":"r-1","createdAt":"2026-11-03T10:06:00.000Z"}"#)
    try await client(transport).relay(caseId: "c-1", body: "今から電話するね")
    let request = try #require(transport.requests.first)
    #expect(request.url?.path == "/cases/c-1/relay")
    #expect(try bodyJSON(request)["body"] as? String == "今から電話するね")
  }

  @Test("解決は POST /cases/{id}/resolve")
  func resolves() async throws {
    let transport = StubTransport(
      status: 200, body: caseJSON(state: "resolved", assignee: ("m-1", "作者")))
    let item = try await client(transport).resolve(caseId: "c-1")
    #expect(item.state == .resolved)
    #expect(transport.requests.first?.url?.path == "/cases/c-1/resolve")
  }

  @Test("409 で受け持ちがいれば「(名前)が対応中」を伝える")
  func conflictBecomesTaken() {
    #expect(
      Problem(APIError.conflict(code: "already_accepted", assigneeName: "妹"), joining: false)
        == .taken(by: "妹"))
    #expect(
      Problem(APIError.conflict(code: "already_resolved", assigneeName: "妹"), joining: false)
        == .resolved)
  }
}

@Suite("家族のカード")
struct FamilyCardTests {
  @Test("誰も引き受けていなければ、引き受けると電話するを出す")
  func notified() throws {
    let card = FamilyCard(try decodeCase(caseJSON()), me: "m-1")
    #expect(card.actions == [.accept, .call])
    #expect(card.status == nil)
  }

  @Test("自分が受け持ちなら、母に返事する、電話する、解決を出す")
  func mine() throws {
    let card = FamilyCard(
      try decodeCase(caseJSON(state: "accepted", assignee: ("m-1", "作者"))), me: "m-1")
    #expect(card.actions == [.reply, .call, .resolve])
    #expect(card.status == "作者が対応中")
  }

  @Test("ほかの人が受け持ちなら「(名前)が対応中」で、返事も解決も出さない")
  func someoneElse() throws {
    let card = FamilyCard(
      try decodeCase(caseJSON(state: "accepted", assignee: ("m-2", "妹"))), me: "m-1")
    #expect(card.status == "妹が対応中")
    #expect(card.actions == [.call])
  }

  @Test("解決したら解決とだけ出す")
  func resolved() throws {
    let card = FamilyCard(
      try decodeCase(caseJSON(state: "resolved", assignee: ("m-2", "妹"))), me: "m-1")
    #expect(card.status == "解決")
    #expect(card.actions.isEmpty)
  }

  @Test("ボタンの文字は1語の動詞")
  func titles() {
    #expect(CardAction.allCases.map(\.title) == ["引き受ける", "母に返事する", "電話する", "解決"])
  }
}

@Suite("母の画面の知らせ")
struct ProtectedNoticeTests {
  @Test("家族に知らせた直後は「家族に伝えました」")
  func toldFamily() throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON())], now: tenOClock.addingTimeInterval(5 * 60))
    #expect(notices.map(\.status) == ["家族に伝えました"])
  }

  @Test("何を家族に伝えたかを並べて出す")
  func showsWhatWasTold() throws {
    let notices = ProtectedNotice.notices(from: [try decodeCase(caseJSON())], now: tenOClock)
    #expect(notices.first?.summary == "警察を名乗る電話の相談")
  }

  @Test("30分たっても誰も引き受けなければ「家族から返事がまだ。急ぐなら電話して」")
  func noReplyYet() throws {
    let late = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON())], now: tenOClock.addingTimeInterval(30 * 60))
    #expect(late.map(\.status) == ["家族から返事がまだ。急ぐなら電話して"])
    // The server's watch has run: shown even if this phone's clock is behind.
    let watched = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(renotifiedAt: "2026-11-03T10:31:00.000Z"))],
      now: tenOClock.addingTimeInterval(60))
    #expect(watched.map(\.status) == ["家族から返事がまだ。急ぐなら電話して"])
  }

  @Test("誰も応じていないあいだは、どの時刻でも「解決」や「対応中」と出さない", arguments: [0, 10, 29, 30, 31, 120, 1440])
  func neverSaysHandled(minutes: Int) throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON())], now: tenOClock.addingTimeInterval(Double(minutes) * 60))
    for notice in notices {
      let text = [notice.status, notice.reply?.from, notice.reply?.body].compactMap { $0 }.joined()
      #expect(!text.contains("解決"))
      #expect(!text.contains("対応中"))
      #expect(!text.contains("見ています"))
      #expect(!text.contains("安全"))
    }
  }

  @Test("引き受けたら「(名前)が見ています」")
  func accepted() throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(state: "accepted", assignee: ("m-2", "妹")))], now: tenOClock)
    #expect(notices.map(\.status) == ["妹が見ています"])
  }

  @Test("返事が来たら「(名前)から」と最新の1通")
  func reply() throws {
    let item = try decodeCase(
      caseJSON(
        state: "accepted", assignee: ("m-2", "妹"),
        relays: [
          ("r-1", "m-2", "妹", "見たよ", "2026-11-03T10:06:00.000Z"),
          ("r-2", "m-2", "妹", "今から電話するね", "2026-11-03T10:07:00.000Z"),
        ]))
    let notice = try #require(ProtectedNotice.notices(from: [item], now: tenOClock).first)
    #expect(notice.reply == ProtectedNotice.Reply(relayId: "r-2", from: "妹から", body: "今から電話するね"))
  }

  @Test("解決した相談は、1日以内の返事だけを残して消える")
  func resolved() throws {
    let withReply = try decodeCase(
      caseJSON(
        id: "c-1", state: "resolved", assignee: ("m-2", "妹"),
        relays: [("r-1", "m-2", "妹", "もう大丈夫だよ", "2026-11-03T10:30:00.000Z")]))
    let without = try decodeCase(caseJSON(id: "c-2", state: "resolved", assignee: ("m-2", "妹")))
    let soon = ProtectedNotice.notices(
      from: [withReply, without], now: tenOClock.addingTimeInterval(3600))
    #expect(soon.map(\.id) == ["c-1"])
    #expect(soon.first?.status == nil)
    let nextDay = ProtectedNotice.notices(
      from: [withReply, without], now: tenOClock.addingTimeInterval(26 * 3600))
    #expect(nextDay.isEmpty)
  }

  @Test("並ぶのは新しい3件まで")
  func atMostThree() throws {
    let cases = try (0..<5).map { i in
      try decodeCase(caseJSON(id: "c-\(i)", notifiedAt: "2026-11-03T10:0\(i):00.000Z"))
    }
    let notices = ProtectedNotice.notices(from: cases, now: tenOClock.addingTimeInterval(600))
    #expect(notices.map(\.id) == ["c-4", "c-3", "c-2"])
  }
}

@Suite("返事の読み上げ")
struct ReplyAnnouncerTests {
  private func notice(_ relayId: String, case id: String = "c-1") -> ProtectedNotice {
    ProtectedNotice(
      id: id, status: nil, reply: .init(relayId: relayId, from: "妹から", body: "今から電話するね"))
  }

  @Test("新しい返事を1回だけ読み上げる")
  func speaksOnce() {
    let store = InMemorySpokenStore()
    let announcer = ReplyAnnouncer(store: store)
    #expect(announcer.toSpeak([notice("r-1")]) == ["妹から。今から電話するね"])
    #expect(announcer.toSpeak([notice("r-1")]).isEmpty)
    // A new app launch reads the same store.
    #expect(ReplyAnnouncer(store: store).toSpeak([notice("r-1")]).isEmpty)
  }

  @Test("返事の無い知らせは読み上げない")
  func noReplyNothing() {
    let announcer = ReplyAnnouncer(store: InMemorySpokenStore())
    #expect(announcer.toSpeak([ProtectedNotice(id: "c-1", status: "家族に伝えました", reply: nil)]).isEmpty)
  }

  @Test("2件届いていれば古いほうから読む")
  func oldestFirst() {
    let announcer = ReplyAnnouncer(store: InMemorySpokenStore())
    let newer = ProtectedNotice(
      id: "c-2", status: nil, reply: .init(relayId: "r-2", from: "作者から", body: "電話したよ"))
    #expect(announcer.toSpeak([newer, notice("r-1")]) == ["妹から。今から電話するね", "作者から。電話したよ"])
  }
}

@Suite("電話番号")
struct PhoneNumberTests {
  @Test(
    "ハイフンや空白を除いて tel: にする",
    arguments: [
      ("090-1234-5678", "tel:09012345678"),
      ("03 1234 5678", "tel:0312345678"),
      ("+81 90 1234 5678", "tel:+819012345678"),
      ("(03)1234-5678", "tel:0312345678"),
    ])
  func normalizes(input: String, url: String) throws {
    #expect(try #require(PhoneNumber(input)).url.absoluteString == url)
  }

  @Test("番号に見えないものは受け付けない", arguments: ["", "abc", "123", "0901234567890123", "09012345678;", "+"])
  func rejects(input: String) {
    #expect(PhoneNumber(input) == nil)
  }
}
