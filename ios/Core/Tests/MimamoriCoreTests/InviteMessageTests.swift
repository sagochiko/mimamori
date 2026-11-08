import Foundation
import Testing

@testable import MimamoriCore

@Suite("招待を送る文")
struct InviteMessageTests {
  private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

  /// 2026-11-09 10:38 in Japan.
  private var invite: Invite {
    Invite(code: InviteCode("652936")!, expiresAt: Date(timeIntervalSince1970: 1_794_188_280))
  }

  @Test("期限は「11月9日 10:38」の形で、日本の時刻で書く")
  func expiryFormat() {
    #expect(InviteMessage.expiry(invite.expiresAt, timeZone: tokyo) == "11月9日 10:38")
    // One minute after midnight UTC is 09:01 in Japan, not 00:01.
    let utcMidnight = Date(timeIntervalSince1970: 1_794_182_460)  // 2026-11-09 00:01 UTC
    #expect(InviteMessage.expiry(utcMidnight, timeZone: tokyo) == "11月9日 9:01")
  }

  @Test("送る文に、アプリのリンク、手順の3行、コード、期限が入る")
  func messageCarriesEverything() {
    let text = InviteMessage.text(for: invite, timeZone: tokyo)
    let lines = text.split(separator: "\n").map(String.init)

    #expect(lines.count == 5)
    #expect(lines[0] == "みまもりで家族に入ってください。")
    #expect(lines[1] == "1. このリンクからアプリを入れる https://testflight.apple.com/join/EZhN4k78")
    #expect(lines[2].hasPrefix("2. アプリを開いて「家族」を選び"))
    #expect(lines[2].contains("「見守られる人」"))
    #expect(lines[3] == "3. コード 652936 を入れて「入る」を押す")
    #expect(lines[4] == "コードは11月9日 10:38まで使えます。")
  }

  @Test("リンクは README の「審査員と家族」の公開リンクと同じ")
  func linkIsThePublicTestFlightLink() {
    #expect(InviteMessage.appLink.absoluteString == "https://testflight.apple.com/join/EZhN4k78")
  }

  @Test("コードが変われば、送る文のコードも変わる")
  func codeIsInserted() {
    let other = Invite(code: InviteCode("000123")!, expiresAt: invite.expiresAt)
    let text = InviteMessage.text(for: other, timeZone: tokyo)
    #expect(text.contains("3. コード 000123 を入れて"))
    #expect(!text.contains("652936"))
  }
}
