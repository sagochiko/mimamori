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

  @Test("ひと言だけなら写真も点数も送らない")
  func postNote() async throws {
    let transport = StubTransport(
      status: 201,
      body:
        #"{"id":"s9","memberId":"m-1","displayName":"作者","role":"family","score":null,"note":"いい笑顔","hasPhoto":false,"createdAt":"2026-11-06T21:30:00.000Z"}"#
    )
    _ = try await client(transport).postSmile(note: "いい笑顔")
    let body = try bodyJSON(try #require(transport.requests.first))
    #expect(body["note"] as? String == "いい笑顔")
    #expect(body["photo"] == nil)
    #expect(body["score"] == nil)
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
}
