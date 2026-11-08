import Foundation
import Testing

@testable import MimamoriCore

/// #271: `alert.digest`, the fixed line of the consultation's summary that the server makes from the
/// agent's two choices. Absent from an older server, null before the summary is read.
@Suite("相談の要約の1行")
struct CaseDigestTests {
  private func alertJSON(_ digest: String) -> String {
    #"""
    {"id":"c-1","alertId":"a-1","state":"notified","notifiedAt":"2026-11-03T10:00:00.000Z",
     "resolvedAt":null,"resolvedBy":null,"renotifiedAt":null,"familyNotifiedAt":null,
     "alert":{"level":2,"source":"consult","summary":"警察を名乗る電話の相談","reasons":[],"evidence":[]\#(digest)},
     "aiReply":null}
    """#
  }

  @Test("裏側の1行をそのまま読む")
  func readsDigest() throws {
    let item = try decodeCase(alertJSON(#","digest":"警察を名乗る連絡 / すぐ電話して確かめる""#))
    #expect(item.alert?.digest == "警察を名乗る連絡 / すぐ電話して確かめる")
  }

  @Test(
    "null、欄が無い、空、文字でないときは無しとして読み、相談は読める",
    arguments: [
      #","digest":null"#, "", #","digest":"""#, #","digest":"  ""#, #","digest":3"#,
    ])
  func readsNone(_ digest: String) throws {
    let item = try decodeCase(alertJSON(digest))
    #expect(item.alert?.summary == "警察を名乗る電話の相談")
    #expect(item.alert?.digest == nil)
  }

  @Test("前の版の形(caseJSON)も無しとして読む")
  func olderShape() throws {
    #expect(try decodeCase(caseJSON()).alert?.digest == nil)
  }
}
