import Foundation
import Testing

@testable import MimamoriCore

/// `familyNotifiedAt` as the server sends it: a time, null while no family device took the notice,
/// or no key at all (a server from before #60).
enum FamilyNotified {
  case at(String)
  case null
  case missing
}

/// The shape `GET /cases` answers with (server/src/cases.ts, CaseView).
func caseJSON(
  id: String = "c-1",
  state: String = "notified",
  resolvedBy: (id: String, name: String)? = nil,
  notifiedAt: String = "2026-11-03T10:00:00.000Z",
  renotifiedAt: String? = nil,
  aiReply: String? = nil,
  family: FamilyNotified = .at("2026-11-03T10:00:01.000Z")
) -> String {
  let resolvedByJSON =
    resolvedBy.map { #"{"memberId":"\#($0.id)","displayName":"\#($0.name)"}"# } ?? "null"
  let familyJSON: String =
    switch family {
    case .at(let time): #""familyNotifiedAt":"\#(time)","#
    case .null: #""familyNotifiedAt":null,"#
    case .missing: ""
    }
  return #"""
    {"id":"\#(id)","alertId":"a-1","state":"\#(state)","notifiedAt":"\#(notifiedAt)",
     "resolvedAt":\#(state == "resolved" ? "\"2026-11-03T11:00:00.000Z\"" : "null"),
     "resolvedBy":\#(resolvedByJSON),
     "renotifiedAt":\#(renotifiedAt.map { "\"\($0)\"" } ?? "null"),\#(familyJSON)
     "alert":{"level":1,"source":"call","summary":"警察を名乗る電話の相談","reasons":["口座の移し替えを求めた"]},
     "aiReply":\#(aiReply.map { "\"\($0)\"" } ?? "null")}
    """#
}

func decodeCase(_ json: String) throws -> Case {
  try APIClient.decoder.decode(Case.self, from: Data(json.utf8))
}

let tenOClock = try! Date("2026-11-03T10:00:00Z", strategy: .iso8601)

@Suite("相談の形")
struct CaseShapeTests {
  @Test("裏側の相談を読む。知らせの1行、理由、AI の答え、解決した人が入る")
  func decodesFullCase() throws {
    let item = try decodeCase(
      caseJSON(state: "resolved", resolvedBy: ("m-2", "妹"), aiReply: "送金はしないで"))
    #expect(item.state == .resolved)
    #expect(item.resolvedBy == CaseMember(memberId: "m-2", displayName: "妹"))
    #expect(item.alert?.level == .doNotOpen)
    #expect(item.alert?.summary == "警察を名乗る電話の相談")
    #expect(item.alert?.reasons == ["口座の移し替えを求めた"])
    #expect(item.aiReply == "送金はしないで")
  }

  @Test("新しい欄が無い古い形も読める")
  func decodesOldShape() throws {
    let json = #"""
      {"id":"c-1","alertId":null,"state":"notified",
       "notifiedAt":"2026-11-03T00:00:00.123Z","resolvedAt":null}
      """#
    let item = try decodeCase(json)
    #expect(item.alert == nil)
    #expect(item.resolvedBy == nil)
  }

  @Test("家族に届いた時刻を読む。null なら届いていない")
  func decodesFamilyNotifiedAt() throws {
    let told = try decodeCase(caseJSON(family: .at("2026-11-03T10:00:01.000Z")))
    #expect(told.familyNotifiedAt == (try Date("2026-11-03T10:00:01Z", strategy: .iso8601)))
    #expect(try decodeCase(caseJSON(family: .null)).familyNotifiedAt == nil)
  }

  @Test("届いた時刻の欄が無い古い形は、届いた相談として読む")
  func missingFamilyNotifiedAtReadsAsTold() throws {
    let item = try decodeCase(caseJSON(family: .missing))
    #expect(item.familyNotifiedAt != nil)
    #expect(item.familyWasTold)
  }

  @Test("前の版の裏側が返す accepted は、解決していない相談として読む")
  func readsOldAcceptedAsOpen() throws {
    let item = try decodeCase(caseJSON(state: "accepted"))
    #expect(item.state == .notified)
  }

  @Test("知らない状態は読まない", arguments: ["", "done", "RESOLVED"])
  func rejectsUnknownState(state: String) {
    #expect(throws: (any Error).self) { _ = try decodeCase(caseJSON(state: state)) }
  }
}

@Suite("APIClient: 相談")
struct CaseAPITests {
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

  @Test("解決は POST /cases/{id}/resolve")
  func resolves() async throws {
    let transport = StubTransport(
      status: 200, body: caseJSON(state: "resolved", resolvedBy: ("m-1", "作者")))
    let item = try await client(transport).resolve(caseId: "c-1")
    #expect(item.state == .resolved)
    #expect(item.resolvedBy?.displayName == "作者")
    #expect(transport.requests.first?.url?.path == "/cases/c-1/resolve")
    #expect(transport.requests.first?.httpMethod == "POST")
  }
}

@Suite("家族のカード")
struct FamilyCardTests {
  @Test("解決していなければ「まだ解決していない」で、電話すると解決を出す")
  func open() throws {
    let card = FamilyCard(try decodeCase(caseJSON()))
    #expect(card.status == "まだ解決していない")
    #expect(card.actions == [.call, .resolve])
  }

  @Test("前の版で引き受けた相談も、どの家族にも同じカードで出す")
  func oldAcceptedIsTheSameCard() throws {
    let card = FamilyCard(try decodeCase(caseJSON(state: "accepted")))
    #expect(card.status == "まだ解決していない")
    #expect(card.actions == [.call, .resolve])
  }

  @Test("解決したら「(名前)が解決」とだけ出す")
  func resolved() throws {
    let card = FamilyCard(try decodeCase(caseJSON(state: "resolved", resolvedBy: ("m-2", "妹"))))
    #expect(card.status == "妹が解決")
    #expect(card.actions.isEmpty)
  }

  @Test("解決した人が分からなければ「家族が解決」")
  func resolvedByUnknown() throws {
    let card = FamilyCard(try decodeCase(caseJSON(state: "resolved")))
    #expect(card.status == "家族が解決")
  }

  @Test("ボタンは電話すると解決の2つだけ")
  func titles() {
    #expect(CardAction.allCases.map(\.title) == ["電話する", "解決"])
  }
}

// #60: a mistaken "解決" stops the 30-minute watch, takes the case off her screen, and tells the
// rest of the family, so pressing it asks first.
@Suite("解決の確かめ")
struct ResolveConfirmationTests {
  @Test("確かめのボタンは「解決にする」と「やめる」")
  func titles() {
    #expect(ResolveChoice.allCases.map(\.title) == ["解決にする", "やめる"])
  }

  @Test("「解決」を押すと、送らずに確かめる")
  func askFirst() throws {
    let item = try decodeCase(caseJSON())
    var confirmation = ResolveConfirmation()
    confirmation.ask(item)
    #expect(confirmation.asking == item)
  }

  @Test("「やめる」なら何も送らず、確かめを閉じる")
  func cancelSendsNothing() throws {
    var confirmation = ResolveConfirmation()
    confirmation.ask(try decodeCase(caseJSON()))
    #expect(confirmation.choose(.cancel) == nil)
    #expect(confirmation.asking == nil)
    // Dismissing the dialog after that sends nothing either.
    #expect(confirmation.choose(.cancel) == nil)
  }

  @Test("「解決にする」なら、その相談を送る")
  func resolveSendsTheCase() throws {
    let item = try decodeCase(caseJSON(id: "c-9"))
    var confirmation = ResolveConfirmation()
    confirmation.ask(item)
    #expect(confirmation.choose(.resolve)?.id == "c-9")
    #expect(confirmation.asking == nil)
  }

  @Test("確かめていなければ「解決にする」でも送らない")
  func nothingAskedSendsNothing() {
    var confirmation = ResolveConfirmation()
    #expect(confirmation.choose(.resolve) == nil)
  }

  @Test("一度送ったら、続けて押しても2回は送らない")
  func sendsOnce() throws {
    var confirmation = ResolveConfirmation()
    confirmation.ask(try decodeCase(caseJSON()))
    #expect(confirmation.choose(.resolve) != nil)
    #expect(confirmation.choose(.resolve) == nil)
  }

  @Test("解決した相談には確かめを出さない")
  func resolvedIsNotAsked() throws {
    var confirmation = ResolveConfirmation()
    confirmation.ask(try decodeCase(caseJSON(state: "resolved", resolvedBy: ("m-2", "妹"))))
    #expect(confirmation.asking == nil)
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

  @Test("30分たっても解決しなければ「家族から返事がまだ。急ぐなら電話して」")
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

  @Test("解決していないあいだは、どの時刻でも「解決」や「見ています」と出さない", arguments: [0, 10, 29, 30, 31, 120, 1440])
  func neverSaysHandled(minutes: Int) throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON()), try decodeCase(caseJSON(id: "c-2", state: "accepted"))],
      now: tenOClock.addingTimeInterval(Double(minutes) * 60))
    #expect(notices.count == 2)
    for notice in notices {
      let text = [notice.status, notice.summary].compactMap { $0 }.joined()
      #expect(!text.contains("解決"))
      #expect(!text.contains("対応中"))
      #expect(!text.contains("見ています"))
      // Only the two fixed lines: no "(名前)から" or "(名前)が見ています".
      #expect([ProtectedNotice.toldFamily, ProtectedNotice.noReplyYet].contains(notice.status))
      #expect(!text.contains("安全"))
    }
  }

  // #60: while no family device took the notice, she must not think the family knows.
  @Test("家族に届いていなければ「家族に届いていません。急ぐなら電話して」", arguments: [0, 10, 29, 30, 31, 120])
  func notReached(minutes: Int) throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(family: .null))], now: tenOClock.addingTimeInterval(Double(minutes) * 60))
    #expect(notices.map(\.status) == ["家族に届いていません。急ぐなら電話して"])
    #expect(ProtectedNotice.notReached == "家族に届いていません。急ぐなら電話して")
  }

  @Test("届いていない相談は、裏側の30分の見張りが走ったあとも「家族に届いていません」")
  func notReachedOverWatch() throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(renotifiedAt: "2026-11-03T10:31:00.000Z", family: .null))],
      now: tenOClock.addingTimeInterval(40 * 60))
    #expect(notices.map(\.status) == [ProtectedNotice.notReached])
  }

  @Test("送り直しが届けば「家族に伝えました」に、30分たっていれば「家族から返事がまだ」に戻る")
  func backToToldOnceDelivered() throws {
    let now = tenOClock.addingTimeInterval(10 * 60)
    let before = ProtectedNotice.notices(from: [try decodeCase(caseJSON(family: .null))], now: now)
    let after = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(family: .at("2026-11-03T10:05:00.000Z")))], now: now)
    #expect(before.map(\.status) == [ProtectedNotice.notReached])
    #expect(after.map(\.status) == [ProtectedNotice.toldFamily])
    let late = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(family: .at("2026-11-03T10:05:00.000Z")))],
      now: tenOClock.addingTimeInterval(31 * 60))
    #expect(late.map(\.status) == [ProtectedNotice.noReplyYet])
  }

  @Test("届いていない相談も、解決したら母の画面から消える")
  func resolvedUntoldLeaves() throws {
    let resolved = try decodeCase(caseJSON(state: "resolved", resolvedBy: ("m-2", "妹"), family: .null))
    #expect(ProtectedNotice.notices(from: [resolved], now: tenOClock.addingTimeInterval(60)).isEmpty)
  }

  @Test("届いた相談と届いていない相談は、それぞれの文言で並ぶ")
  func mixed() throws {
    let told = try decodeCase(caseJSON(id: "c-1", notifiedAt: "2026-11-03T09:59:00.000Z"))
    let untold = try decodeCase(caseJSON(id: "c-2", family: .null))
    let notices = ProtectedNotice.notices(from: [told, untold], now: tenOClock.addingTimeInterval(60))
    #expect(notices.map(\.status) == [ProtectedNotice.notReached, ProtectedNotice.toldFamily])
  }

  @Test("届いた欄が無い古い形は、今までどおり「家族に伝えました」")
  func missingKeyIsTold() throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON(family: .missing))], now: tenOClock.addingTimeInterval(60))
    #expect(notices.map(\.status) == [ProtectedNotice.toldFamily])
  }

  @Test("解決した相談は母の画面から消える")
  func resolvedLeaves() throws {
    let resolved = try decodeCase(caseJSON(id: "c-1", state: "resolved", resolvedBy: ("m-2", "妹")))
    let open = try decodeCase(caseJSON(id: "c-2", notifiedAt: "2026-11-03T09:59:00.000Z"))
    let notices = ProtectedNotice.notices(from: [resolved, open], now: tenOClock.addingTimeInterval(60))
    #expect(notices.map(\.id) == ["c-2"])
  }

  @Test("3日より前の解決していない相談は出さない")
  func oldOpenLeaves() throws {
    let notices = ProtectedNotice.notices(
      from: [try decodeCase(caseJSON())], now: tenOClock.addingTimeInterval(3 * 24 * 3600))
    #expect(notices.isEmpty)
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
