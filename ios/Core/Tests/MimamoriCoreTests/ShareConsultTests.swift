import Foundation
import Testing

@testable import MimamoriCore

@Suite("共有した画像の相談")
struct ShareConsultTests {
  static let image = ConsultImage(mediaType: .jpeg, data: Data([0xFF, 0xD8, 0xFF]), size: PixelSize(width: 1179, height: 2556))

  @Test("POST /consult に画像を base64 で送り、言葉が無ければ text を付けない")
  func sendsImage() async throws {
    let transport = StubTransport(
      status: 200, body: #"{"reply":"ここ","speak":"ここ","tap":{"x":540,"y":1210},"handoff":false}"#)
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))

    let answer = try await client.consult(image: Self.image)

    let request = try #require(transport.requests.first)
    #expect(request.url?.path == "/consult")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    let json = try bodyJSON(request)
    #expect(json["text"] == nil)
    #expect(json["history"] == nil)
    let image = try #require(json["image"] as? [String: Any])
    #expect(image["mediaType"] as? String == "image/jpeg")
    #expect(image["data"] as? String == "/9j/")
    #expect(image["width"] as? Int == 1179)
    #expect(image["height"] as? Int == 2556)
    #expect(answer.tap == ConsultAnswer.Tap(x: 540, y: 1210))
  }

  @Test("丸を付けたら、押せたらもう一度見せてと続ける")
  func asksForNext() {
    let answer = ConsultAnswer(reply: "丸のところを押して", speak: "丸のところを押して", tap: .init(x: 1, y: 2), handoff: false)
    #expect(ShareConsult.reply(for: answer) == "丸のところを押して。押せたらもう一度見せて")
  }

  @Test("拡張では、画像だけへの聞き返しをアプリで話してもらう1行に言い換える")
  func extensionRewordsAsk() {
    let ask = ConsultAnswer(reply: "この画面で何をしたい?", speak: "この画面で何をしたい?", tap: nil, handoff: false)
    #expect(ShareConsult.extensionReply(for: ask) == "みまもりを開いて何をしたいか教えてね")
    // In the app's chat the line stays as it is.
    #expect(ShareConsult.reply(for: ask) == "この画面で何をしたい?")
  }

  @Test("拡張でも、聞き返し以外の答えは今までどおり")
  func extensionKeepsOthers() {
    let circled = ConsultAnswer(reply: "丸のところを押して", speak: "丸のところを押して", tap: .init(x: 1, y: 2), handoff: false)
    #expect(ShareConsult.extensionReply(for: circled) == ShareConsult.reply(for: circled))
    let warned = ConsultAnswer(reply: "家族に伝えました", speak: "家族に伝えました", tap: nil, handoff: true)
    #expect(ShareConsult.extensionReply(for: warned) == "家族に伝えました")
  }

  @Test("丸が無ければ答えのまま")
  func noCircle() {
    let answer = ConsultAnswer(reply: "家族に伝えました", speak: "家族に伝えました", tap: nil, handoff: true)
    #expect(ShareConsult.reply(for: answer) == "家族に伝えました")
  }

  @Test("丸の場所は、送った画像の座標を元の画像に戻したもの")
  func circleOnOriginal() {
    let sent = PixelSize(width: 1188, height: 2576)
    let original = PixelSize(width: 1290, height: 2796)
    let answer = ConsultAnswer(reply: "x", speak: "x", tap: .init(x: 594, y: 1288), handoff: false)
    #expect(ShareConsult.circle(for: answer, sent: sent, original: original) == PixelPoint(x: 645, y: 1398))
    let off = ConsultAnswer(reply: "x", speak: "x", tap: .init(x: 1188, y: 10), handoff: false)
    #expect(ShareConsult.circle(for: off, sent: sent, original: original) == nil)
  }
}
