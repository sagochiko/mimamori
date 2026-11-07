import Foundation
import Testing

@testable import MimamoriCore

/// The photo button in her chat (#221): she picks a screenshot, it goes to POST /consult the same way
/// as from the share sheet, and her line and the answer join the conversation; the image does not.
@MainActor
@Suite("チャットから見せた画像の相談")
struct PictureConsultTests {
  static let image = ConsultImage(
    mediaType: .jpeg, data: Data([0xFF, 0xD8, 0xFF]), size: PixelSize(width: 1179, height: 2556))
  static let circled = ConsultAnswer(
    reply: "丸のところを押して", speak: "丸のところを押して", tap: .init(x: 540, y: 1210), handoff: false)

  // MARK: Session

  @Test("Session から画像と書いた言葉を送り、前のやり取りは付けない")
  func sessionSendsImage() async throws {
    let transport = StubTransport(
      status: 200, body: #"{"reply":"ここ","speak":"ここ","tap":{"x":540,"y":1210},"handoff":false}"#)
    let session = Session(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample),
      marker: InMemoryInstallMarker(marked: true))

    let answer = try await session.consult(image: Self.image, text: "これどこ押すの")

    let request = try #require(transport.requests.first)
    #expect(request.url?.path == "/consult")
    let json = try bodyJSON(request)
    #expect(json["text"] as? String == "これどこ押すの")
    #expect(json["history"] == nil)
    let image = try #require(json["image"] as? [String: Any])
    #expect(image["width"] as? Int == 1179)
    #expect(image["height"] as? Int == 2556)
    #expect(answer.tap == ConsultAnswer.Tap(x: 540, y: 1210))
  }

  @Test("画像の相談で 401 が返ると、鍵を消して役の選択に戻る")
  func sessionUnauthorized() async throws {
    let store = InMemoryDeviceKeyStore(.sample)
    let session = Session(
      baseURL: testBaseURL, transport: StubTransport(status: 401), store: store,
      marker: InMemoryInstallMarker(marked: true))

    await #expect(throws: APIError.unauthorized) {
      _ = try await session.consult(image: Self.image)
    }

    #expect(session.route == .chooseRole)
    #expect(store.load() == nil)
  }

  // MARK: 送れる大きさ

  @Test("base64 で300万字までなら送れ、1バイトでも超えれば送らない")
  func serverLimit() {
    // 2,250,000 bytes are exactly 3,000,000 base64 characters.
    #expect(ConsultImage.fitsServer(byteCount: 2_250_000))
    #expect(!ConsultImage.fitsServer(byteCount: 2_250_001))
    #expect(ConsultImage.maxBase64Characters == 3_000_000)
  }

  // MARK: 画面の流れ

  @Test("写真を選ぶと、母の側の1行を出して画像を送る")
  func pictureSends() {
    var flow = VoiceConsult()
    #expect(flow.pictured("", at: .t0) == [.stopSpeaking, .sendPicture(text: "")])
    #expect(flow.phase == .thinking(said: VoiceConsult.pictureLine))
    #expect(!flow.acceptsText)
  }

  @Test("欄に書いた言葉があれば、1行にも送る言葉にも入れる")
  func pictureWithText() {
    var flow = VoiceConsult()
    #expect(
      flow.pictured("  これどこ押すの \n", at: .t0) == [.stopSpeaking, .sendPicture(text: "これどこ押すの")])
    #expect(flow.phase == .thinking(said: "\(VoiceConsult.pictureLine)。これどこ押すの"))
  }

  @Test("書いた言葉は1000字で切る")
  func pictureTextCut() {
    var flow = VoiceConsult()
    let long = String(repeating: "あ", count: VoiceConsult.maxCharacters + 5)
    let effects = flow.pictured(long, at: .t0)
    #expect(
      effects == [
        .stopSpeaking,
        .sendPicture(text: String(repeating: "あ", count: VoiceConsult.maxCharacters)),
      ])
  }

  @Test("聞いているあいだと答えを待つあいだは、写真を送らない")
  func pictureIgnoredWhileBusy() {
    var listening = VoiceConsult()
    _ = listening.micTapped(at: .t0)
    #expect(listening.pictured("", at: .t0).isEmpty)
    #expect(listening.phase == .listening(heard: ""))

    var thinking = VoiceConsult()
    _ = thinking.typed("Wi-Fi がつながらない", at: .t0)
    #expect(thinking.pictured("", at: .t0).isEmpty)
    #expect(thinking.phase == .thinking(said: "Wi-Fi がつながらない"))
  }

  @Test("声で聞いたあとでも、画像の答えは読み上げない")
  func pictureNeverReadAloud() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("どこを押すの", isFinal: true, at: .t0)
    _ = flow.answered(Self.circled, readsAloud: true)

    _ = flow.pictured("", at: .t0)
    #expect(flow.answered(Self.circled, readsAloud: true).isEmpty)
    #expect(flow.phase == .answered(said: VoiceConsult.pictureLine, answer: Self.circled))
  }

  @Test("画像の答えのあとに声で聞けば、今までどおり読み上げる")
  func voiceAfterPictureStillReads() {
    var flow = VoiceConsult()
    _ = flow.pictured("", at: .t0)
    _ = flow.answered(Self.circled, readsAloud: true)

    _ = flow.micTapped(at: .t0)
    _ = flow.heard("ありがとう", isFinal: true, at: .t0)
    #expect(
      flow.answered(VoiceConsultTests.police, readsAloud: true) == [
        .speak(VoiceConsultTests.police.speak)
      ])
  }

  @Test("読めない画像は送らず、短い印だけを出す。会話にも何も残さない")
  func unreadablePicture() {
    var flow = VoiceConsult()
    flow.pictureUnreadable()
    #expect(flow.phase == .failed(.unreadableImage))
    #expect(ConsultFailure.unreadableImage.text == "画像を読めません")
    #expect(!ConsultFailure.unreadableImage.accessibilityHint.isEmpty)
    #expect(flow.acceptsText)

    var thinking = VoiceConsult()
    _ = thinking.typed("Wi-Fi がつながらない", at: .t0)
    thinking.pictureUnreadable()
    #expect(thinking.phase == .thinking(said: "Wi-Fi がつながらない"))
  }

  @Test("1行には数字も画像の中身も入らない")
  func lineIsFixed() {
    let digits = VoiceConsult.pictureLine.unicodeScalars.filter {
      $0.properties.generalCategory == .decimalNumber
    }
    #expect(digits.isEmpty)
    #expect(!VoiceConsult.pictureLine.isEmpty)
  }

  // MARK: 会話の記録

  @Test("会話に残るのは母の側の1行と答えの文だけで、1行は次の相談の前のやり取りに入る")
  func keepsLineAndAnswerOnly() {
    let store = MemoryChatStore()
    var keeper = ChatKeeper(store: store)
    keeper.pictured(VoiceConsult.pictureLine, at: .t0)
    keeper.answered(ShareConsult.reply(for: Self.circled), at: .t0)

    let messages = keeper.log.messages
    #expect(messages.map(\.role) == [.protected, .ai])
    #expect(messages.map(\.text) == [VoiceConsult.pictureLine, "丸のところを押して。押せたらもう一度見せて"])
    #expect(!messages[0].isLocalOnly)
    #expect(keeper.log.history(at: .t0.addingTimeInterval(60)).map(\.text) == messages.map(\.text))

    // What the file holds is the same two lines and nothing else.
    let saved = ChatLog.restored(from: store.data, at: .t0)
    #expect(saved.messages.map(\.text) == messages.map(\.text))
  }
}
