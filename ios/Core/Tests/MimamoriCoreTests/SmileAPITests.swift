import Foundation
import Testing

@testable import MimamoriCore

@Suite("笑顔の API")
struct SmileAPITests {
  private func client(_ transport: StubTransport) -> APIClient {
    APIClient(baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
  }

  @Test("GET /smiles を読む。抜けた人の role は nil になる")
  func list() async throws {
    let transport = StubTransport(
      status: 200,
      body: #"""
        {"smiles":[
          {"id":"s2","memberId":"m-2","displayName":"作者","role":"family","score":null,"note":"おはよう","hasPhoto":false,"createdAt":"2026-11-06T22:10:00.000Z"},
          {"id":"s1","memberId":"m-1","displayName":"家族","role":null,"score":0.8,"note":null,"hasPhoto":true,"createdAt":"2026-11-06T21:30:00.000Z"}
        ],"deadlineHour":10}
        """#)
    let board = try await client(transport).smiles()

    #expect(transport.requests.first?.url?.path == "/smiles")
    #expect(transport.requests.first?.httpMethod == "GET")
    #expect(board.deadlineHour == 10)
    #expect(board.smiles.map(\.id) == ["s2", "s1"])
    #expect(board.smiles[0].note == "おはよう")
    #expect(board.smiles[0].hasPhoto == false)
    #expect(board.smiles[1].role == nil)
    #expect(board.smiles[1].score == 0.8)
  }

  @Test("deadlineHour の無い答えは既定の時刻として読む")
  func listWithoutHour() async throws {
    let transport = StubTransport(status: 200, body: #"{"smiles":[]}"#)
    let board = try await client(transport).smiles()
    #expect(board.deadlineHour == SmileBoard.defaultDeadlineHour)
  }

  @Test("写真は base64 で、点数とひと言と一緒に POST /smiles に送る")
  func post() async throws {
    let transport = StubTransport(
      status: 201,
      body:
        #"{"id":"s9","memberId":"m-1","displayName":"母","role":"protected","score":0.7,"note":null,"hasPhoto":true,"createdAt":"2026-11-06T21:30:00.000Z"}"#
    )
    let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
    let smile = try await client(transport).postSmile(photoJPEG: jpeg, score: 0.7)

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/smiles")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    let body = try bodyJSON(request)
    #expect(body["photo"] as? String == jpeg.base64EncodedString())
    #expect(body["score"] as? Double == 0.7)
    #expect(body["note"] == nil)
    #expect(smile.id == "s9")
  }

  @Test("ひと言だけなら決まった語の ID を送り、写真も点数も送らない")
  func postNote() async throws {
    let transport = StubTransport(
      status: 201,
      body: #"{"id":"s9","memberId":"m-1","displayName":"作者","role":"family","score":null,"note":"いい笑顔","hasPhoto":false,"createdAt":"2026-11-06T21:30:00.000Z"}"#
    )
    _ = try await client(transport).postSmile(note: .niceSmile)
    let body = try bodyJSON(try #require(transport.requests.first))
    #expect(body["note"] as? String == "nice-smile")
    #expect(body["photo"] == nil)
    #expect(body["score"] == nil)
  }

  @Test("決まった語は裏側と同じ ID と言葉で、4〜6個")
  func setWords() {
    #expect((4...6).contains(SmileNote.allCases.count))
    #expect(
      SmileNote.allCases.map { "\($0.rawValue)=\($0.text)" } == [
        "good-morning=おはよう", "nice-smile=いい笑顔", "thanks=ありがとう", "doing-fine=元気だよ", "see-you=またね",
      ])
  }

  @Test("写真は鍵を付けて GET /smiles/{id}/photo から受け取る")
  func photo() async throws {
    let transport = StubTransport(status: 200, body: "jpeg")
    let data = try await client(transport).smilePhoto(id: "s1")
    let request = try #require(transport.requests.first)
    #expect(request.url?.path == "/smiles/s1/photo")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(data == Data("jpeg".utf8))
  }

  @Test("別の家族の写真は 403 のエラーになる")
  func photoForbidden() async throws {
    let transport = StubTransport(status: 403, body: #"{"error":"not_your_family"}"#)
    await #expect(throws: APIError.http(status: 403)) {
      _ = try await client(transport).smilePhoto(id: "s1")
    }
  }

  @Test("母の笑顔を待つ時刻を PUT /families/me/smile-deadline に送る")
  func deadline() async throws {
    let transport = StubTransport(status: 200, body: #"{"deadlineHour":11}"#)
    let hour = try await client(transport).setSmileDeadline(hour: 11)
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/families/me/smile-deadline")
    #expect(try bodyJSON(request)["hour"] as? Int == 11)
    #expect(hour == 11)
  }

  @Test("自分の笑顔の知らせの設定を GET /members/me/settings で読む")
  func readSettings() async throws {
    let transport = StubTransport(status: 200, body: #"{"smileNotify":false,"smileMissedNotify":true}"#)
    let settings = try await client(transport).memberSettings()
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/members/me/settings")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(settings == MemberSettings(smileNotify: false, smileMissedNotify: true))
  }

  @Test("PUT /members/me/settings には切り替えたキーだけを送り、裏側の答えを返す")
  func writeSettings() async throws {
    let transport = StubTransport(status: 200, body: #"{"smileNotify":true,"smileMissedNotify":false}"#)
    let saved = try await client(transport).setMemberSettings(.smileMissedNotify(false))
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/members/me/settings")
    let body = try bodyJSON(request)
    #expect(body["smileMissedNotify"] as? Bool == false)
    // The other switch is left out, so a screen that could not read it never writes its default.
    #expect(body["smileNotify"] == nil)
    #expect(body.count == 1)
    #expect(saved == MemberSettings(smileNotify: true, smileMissedNotify: false))
  }

  @Test("切り替えを今の設定に当てると、そのキーだけが変わる")
  func applyChange() {
    let now = MemberSettings(smileNotify: true, smileMissedNotify: true)
    #expect(MemberSettingsChange.smileNotify(false).applied(to: now) == MemberSettings(smileNotify: false, smileMissedNotify: true))
    #expect(MemberSettingsChange.smileMissedNotify(false).applied(to: now) == MemberSettings(smileNotify: true, smileMissedNotify: false))
  }

  @Test("設定の既定は2つともオン")
  func settingsDefault() {
    #expect(MemberSettings() == MemberSettings(smileNotify: true, smileMissedNotify: true))
  }

  @Test("今日の母の笑顔は、その日に母が撮った写真のうち一番新しいもの")
  func todaysProtected() throws {
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = tokyo
    let now = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 8)))
    func smile(_ id: String, _ role: Role?, hoursAgo: Double, photo: Bool = true) -> Smile {
      Smile(
        id: id, memberId: "m", displayName: "x", role: role, score: nil, note: nil, hasPhoto: photo,
        createdAt: now.addingTimeInterval(-hoursAgo * 3600))
    }
    let board = SmileBoard(
      smiles: [
        smile("family-today", .family, hoursAgo: 0.5),
        smile("note-today", .protected, hoursAgo: 0.7, photo: false),
        smile("mother-today", .protected, hoursAgo: 1),
        smile("mother-earlier", .protected, hoursAgo: 2),
        smile("mother-yesterday", .protected, hoursAgo: 10),
      ], deadlineHour: 9)
    #expect(board.todaysProtectedSmile(now: now, calendar: calendar)?.id == "mother-today")
    #expect(
      board.todaysProtectedSmile(now: now.addingTimeInterval(86_400), calendar: calendar) == nil)
  }
  @Test("画面に並べるのは写真のある笑顔だけで、ひと言だけの行は出さない")
  func photosOnly() {
    func smile(_ id: String, photo: Bool, note: String?) -> Smile {
      Smile(
        id: id, memberId: "m", displayName: "x", role: .family, score: nil, note: note, hasPhoto: photo,
        createdAt: Date(timeIntervalSince1970: 0))
    }
    let board = SmileBoard(smiles: [
      smile("note-only", photo: false, note: "いい笑顔"),
      smile("photo", photo: true, note: nil),
      smile("photo-and-note", photo: true, note: "おはよう"),
      smile("empty", photo: false, note: nil),
    ])
    #expect(board.photos.map(\.id) == ["photo", "photo-and-note"])
    #expect(SmileBoard(smiles: [smile("note-only", photo: false, note: "またね")]).photos.isEmpty)
  }

  // On build 12 her row showed 「見守られる人」 twice: her own smiles, and those of the member she was
  // before reinstalling, which the server keeps (#243). Her screen shows only the family's.
  @Test("母の画面に並べるのは家族の役の写真だけで、見守られる人の笑顔と抜けた人の笑顔は出さない(#243)")
  func familyPhotosOnly() {
    func smile(_ id: String, _ member: String, _ role: Role?, photo: Bool = true) -> Smile {
      Smile(
        id: id, memberId: member, displayName: role == .protected ? "見守られる人" : "家族", role: role,
        score: nil, note: nil, hasPhoto: photo, createdAt: Date(timeIntervalSince1970: 0))
    }
    let board = SmileBoard(smiles: [
      smile("sister", "m-sister", .family),
      smile("her", "m-her", .protected),
      smile("her-before-reinstall", "m-her-old", .protected),
      smile("owner", "m-owner", .family),
      smile("owner-note", "m-owner", .family, photo: false),
      smile("left", "m-left", nil),
    ])
    #expect(board.familyPhotos.map(\.id) == ["sister", "owner"])
    // The family's screen still shows everyone's.
    #expect(board.photos.map(\.id) == ["sister", "her", "her-before-reinstall", "owner", "left"])
  }
}
