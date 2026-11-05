import Foundation
import Testing

@testable import MimamoriCore

@Suite("SMS の仕分けの返事")
struct SMSFilterReplyTests {
  private func data(_ json: String) -> Data { Data(json.utf8) }

  @Test("裏側が junk と答えたら迷惑フォルダに回す")
  func junk() {
    #expect(SMSFilterReply.verdict(statusCode: 200, data: data(#"{"action":"junk"}"#)) == .junk)
  }

  @Test("体験モードのカードが付いていても junk は junk")
  func junkWithCard() {
    let body = #"{"action":"junk","card":{"level":1,"source":"sms","summary":"SMS","reasons":[]}}"#
    #expect(SMSFilterReply.verdict(statusCode: 200, data: data(body)) == .junk)
  }

  @Test(
    "それ以外はすべて通常どおり届ける",
    arguments: [
      #"{"action":"none"}"#,
      #"{"action":"allow"}"#,  // the server never says allow; even if it did, it is not trusted as "fine"
      #"{"action":"JUNK"}"#,
      #"{"action":1}"#,
      #"{}"#,
      #"[]"#,
      "not json",
      "",
    ]
  )
  func otherwiseNone(body: String) {
    #expect(SMSFilterReply.verdict(statusCode: 200, data: data(body)) == .none)
  }

  @Test("200 番台でない答えや、答えが無いときは届ける", arguments: [nil, 0, 301, 404, 429, 500])
  func badStatus(status: Int?) {
    #expect(SMSFilterReply.verdict(statusCode: status, data: data(#"{"action":"junk"}"#)) == .none)
  }

  @Test("本文が無いときは届ける")
  func noData() {
    #expect(SMSFilterReply.verdict(statusCode: 200, data: nil) == .none)
  }
}
