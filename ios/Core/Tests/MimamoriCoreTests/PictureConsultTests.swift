import Foundation
import Testing

@testable import MimamoriCore

/// The photo button in her chat (#221): she picks a screenshot, it goes to POST /consult the same way
/// as from the share sheet, and her words, the image shrunk, and the answer join the conversation
/// on the iPhone (#243).
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

  @Test("写真だけを送ると、吹き出しに言葉は入れず画像を送る(#243)")
  func pictureSends() {
    var flow = VoiceConsult()
    #expect(flow.pictured("", at: .t0) == [.stopSpeaking, .sendPicture(text: "")])
    #expect(flow.phase == .thinking(said: ""))
    #expect(!flow.acceptsText)
  }

  @Test("欄に書いた言葉があれば、「画像を見せました」を付けずにそのまま送る(#243)")
  func pictureWithText() {
    var flow = VoiceConsult()
    #expect(
      flow.pictured("  これどこ押すの \n", at: .t0) == [.stopSpeaking, .sendPicture(text: "これどこ押すの")])
    #expect(flow.phase == .thinking(said: "これどこ押すの"))
  }

  // MARK: 入力欄に付ける(#234)

  @Test("写真を選んでもすぐには送らず、入力欄に付くだけ")
  func attachDoesNotSend() {
    var flow = VoiceConsult()
    let attached = flow.attachPicture()
    #expect(attached)
    #expect(flow.hasPicture)
    #expect(flow.phase == .idle)
    #expect(flow.acceptsText)
  }

  @Test("画像が付いていれば、書いた言葉と一緒に1回で送る")
  func attachedGoesWithTyped() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    #expect(
      flow.typed(" この写真を消したい ", at: .t0) == [.stopSpeaking, .sendPicture(text: "この写真を消したい")])
    #expect(flow.phase == .thinking(said: "この写真を消したい"))
    #expect(!flow.hasPicture)
  }

  // The author changed the form of review 1 of PR #237 on 2026-11-07 (#243): an image alone goes.
  @Test("画像が付いていれば、言葉が無くても送れる(#243)")
  func attachedAloneSends() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    #expect(flow.canSend(draft: "  "))
    #expect(flow.typed("  ", at: .t0) == [.stopSpeaking, .sendPicture(text: "")])
    #expect(flow.phase == .thinking(said: ""))
    #expect(!flow.hasPicture)
  }

  // The hole review 1 of PR #237 found: her answer to the question went without the image, and Claude
  // answered without seeing the screen. The image goes back onto the field and goes with her words.
  @Test("画像だけで送って聞き返されたら、画像を欄に戻し、次の言葉と一緒にもう一度送る(#243)")
  func askedBackKeepsPicture() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    _ = flow.typed("", at: .t0)
    let ask = ConsultAnswer(
      reply: ShareConsult.askPicture, speak: ShareConsult.askPicture, tap: nil, handoff: false)
    #expect(flow.answered(ask, readsAloud: true) == [.keepPicture])
    #expect(flow.hasPicture)
    #expect(flow.acceptsText)
    #expect(flow.typed("容量を空けたい", at: .t0) == [.stopSpeaking, .sendPicture(text: "容量を空けたい")])
    #expect(!flow.hasPicture)
  }

  @Test("聞き返されたあと声で答えても、画像が一緒に行く(#243)")
  func askedBackGoesWithVoice() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    _ = flow.typed("", at: .t0)
    let ask = ConsultAnswer(
      reply: ShareConsult.askPicture, speak: ShareConsult.askPicture, tap: nil, handoff: false)
    _ = flow.answered(ask, readsAloud: false)
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    _ = flow.sendTapped(at: .t0)
    #expect(flow.heard("容量を空けたい", isFinal: true, at: .t0) == [.sendPicture(text: "容量を空けたい")])
  }

  @Test("画像の答えが聞き返しでなければ、画像は欄に戻らない。言葉だけの相談の同じ文でも戻らない")
  func otherAnswersDropPicture() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    _ = flow.typed("", at: .t0)
    #expect(flow.answered(Self.circled, readsAloud: true).isEmpty)
    #expect(!flow.hasPicture)

    var words = VoiceConsult()
    _ = words.typed("これ", at: .t0)
    let ask = ConsultAnswer(
      reply: ShareConsult.askPicture, speak: ShareConsult.askPicture, tap: nil, handoff: false)
    #expect(words.answered(ask, readsAloud: false).isEmpty)
    #expect(!words.hasPicture)
  }

  @Test("画像が付いていても、声で何も聞けなければ何も送らず、画像は欄に残る")
  func notHeardKeepsPicture() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    _ = flow.sendTapped(at: .t0)
    #expect(flow.heard("", isFinal: true, at: .t0).isEmpty)
    #expect(flow.phase == .failed(.notHeard))
    #expect(flow.hasPicture)
  }

  @Test("画像も言葉も無ければ送れない")
  func nothingToSend() {
    var flow = VoiceConsult()
    #expect(!flow.canSend(draft: " \n"))
    #expect(flow.typed(" ", at: .t0).isEmpty)
    #expect(flow.canSend(draft: "Wi-Fi"))
  }

  @Test("外した画像は送らない")
  func removedPictureStays() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    flow.removePicture()
    #expect(!flow.hasPicture)
    #expect(!flow.canSend(draft: ""))
    #expect(flow.typed("Wi-Fi がつながらない", at: .t0) == [.stopSpeaking, .send("Wi-Fi がつながらない")])
  }

  @Test("声で話して送ると、付いた画像も一緒に行き、答えは読み上げない")
  func attachedGoesWithVoice() {
    var flow = VoiceConsult()
    _ = flow.attachPicture()
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    #expect(flow.hasPicture)
    #expect(flow.sendTapped(at: .t0) == [.stopListening])
    #expect(flow.heard("これを消したい", isFinal: true, at: .t0) == [.sendPicture(text: "これを消したい")])
    #expect(flow.phase == .thinking(said: "これを消したい"))
    #expect(!flow.hasPicture)
    #expect(flow.answered(Self.circled, readsAloud: true).isEmpty)
  }

  @Test("声を止めて欄に入れたときと捨てたときは、画像は付いたまま")
  func attachedStaysWithDraftAndTrash() {
    var stopped = VoiceConsult()
    _ = stopped.attachPicture()
    _ = stopped.micTapped(at: .t0)
    _ = stopped.listeningStarted(at: .t0)
    _ = stopped.stopTapped(at: .t0)
    #expect(stopped.heard("これを消したい", isFinal: true, at: .t0) == [.fillDraft("これを消したい")])
    #expect(stopped.hasPicture)

    var trashed = VoiceConsult()
    _ = trashed.attachPicture()
    _ = trashed.micTapped(at: .t0)
    _ = trashed.discardTapped()
    #expect(trashed.hasPicture)
  }

  @Test("聞いているあいだと答えを待つあいだは、画像を付けない")
  func attachIgnoredWhileBusy() {
    var listening = VoiceConsult()
    _ = listening.micTapped(at: .t0)
    let whileListening = listening.attachPicture()
    #expect(!whileListening)
    #expect(!listening.hasPicture)

    var thinking = VoiceConsult()
    _ = thinking.typed("Wi-Fi がつながらない", at: .t0)
    let whileThinking = thinking.attachPicture()
    #expect(!whileThinking)
    #expect(!thinking.canSend(draft: "もう一度"))
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
    #expect(flow.phase == .answered(said: "", answer: Self.circled))
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

  @Test("読み上げの1行には数字も画像の中身も入らない")
  func lineIsFixed() {
    let digits = VoiceConsult.pictureLine.unicodeScalars.filter {
      $0.properties.generalCategory == .decimalNumber
    }
    #expect(digits.isEmpty)
    #expect(!VoiceConsult.pictureLine.isEmpty)
  }

  // MARK: 会話の記録

  @Test("会話には母の言葉と縮めた画像と答えが残り、言葉だけが次の相談の前のやり取りに入る(#243)")
  func keepsWordsPictureAndAnswer() throws {
    let store = MemoryChatStore()
    let pictures = MemoryPictureStore()
    var keeper = ChatKeeper(store: store, pictures: pictures)
    keeper.pictured("これを消したい", picture: Data([1, 2, 3]), at: .t0)
    keeper.answered(ShareConsult.reply(for: Self.circled), at: .t0)

    let messages = keeper.log.messages
    #expect(messages.map(\.role) == [.protected, .ai])
    #expect(messages.map(\.text) == ["これを消したい", "丸のところを押して。押せたらもう一度見せて"])
    let name = try #require(messages[0].picture)
    #expect(messages[1].picture == nil)
    #expect(pictures.files == [name: Data([1, 2, 3])])
    #expect(keeper.picture(for: messages[0]) == Data([1, 2, 3]))
    #expect(keeper.log.history(at: .t0.addingTimeInterval(60)).map(\.text) == messages.map(\.text))

    // The file names the picture; the picture itself is in its own file.
    let saved = ChatLog.restored(from: store.data, at: .t0)
    #expect(saved.messages.map(\.picture) == [name, nil])
    #expect(!(String(data: store.data ?? Data(), encoding: .utf8) ?? "").contains("AQID"))
  }

  @Test("画像だけの吹き出しは、言葉が無いので前のやり取りに入れない(#243)")
  func pictureAloneNotInHistory() {
    var keeper = ChatKeeper(store: MemoryChatStore(), pictures: MemoryPictureStore())
    keeper.pictured("", picture: Data([1]), at: .t0)
    keeper.answered(ShareConsult.askPicture, at: .t0)
    #expect(keeper.log.messages.count == 2)
    #expect(keeper.log.history(at: .t0.addingTimeInterval(60)).map(\.text) == [ShareConsult.askPicture])
  }

  @Test("50件から外れた吹き出しの画像は一緒に消える(#243)")
  func trimmedPictureGoes() {
    let pictures = MemoryPictureStore()
    var keeper = ChatKeeper(store: MemoryChatStore(), pictures: pictures)
    keeper.pictured("", picture: Data([1]), at: .t0)
    #expect(pictures.files.count == 1)
    for i in 0..<(ChatLog.keep - 1) { keeper.answered("答え\(i)", at: .t0) }
    #expect(pictures.files.count == 1)
    keeper.answered("もう1件", at: .t0)
    #expect(keeper.log.messages.count == ChatLog.keep)
    #expect(pictures.files.isEmpty)
  }

  @Test("30日たって読み込みで落ちた吹き出しの画像も消え、残った吹き出しの画像は残る(#243)")
  func agedPictureGoes() throws {
    let store = MemoryChatStore()
    let pictures = MemoryPictureStore()
    var old = ChatKeeper(store: store, pictures: pictures)
    old.pictured("", picture: Data([1]), at: .t0)
    old.pictured("", picture: Data([2]), at: .t0 + ChatLog.keptFor - 10)
    #expect(pictures.files.count == 2)

    var reopened = ChatKeeper(store: store, pictures: pictures)
    reopened.load(at: .t0 + ChatLog.keptFor)
    let kept = try #require(reopened.log.messages.first?.picture)
    #expect(pictures.files == [kept: Data([2])])
  }

  @Test("会話を消すと画像も全部消える(#243)")
  func clearRemovesPictures() {
    let pictures = MemoryPictureStore()
    var keeper = ChatKeeper(store: MemoryChatStore(), pictures: pictures)
    keeper.pictured("", picture: Data([1]), at: .t0)
    keeper.clear()
    #expect(pictures.files.isEmpty)
  }

  @Test("画面のロック中で会話を読めないあいだは、画像も書かない")
  func lockedWritesNoPicture() {
    let store = MemoryChatStore()
    store.locked = true
    let pictures = MemoryPictureStore()
    var keeper = ChatKeeper(store: store, pictures: pictures)
    keeper.pictured("これ", picture: Data([1]), at: .t0)
    #expect(pictures.files.isEmpty)
    #expect(keeper.log.messages.first?.picture == nil)
  }

  @Test("前の形のファイル(画像の欄が無い)もそのまま読める")
  func oldFileReads() throws {
    let old = #"{"messages":[{"id":"8D6B1F3E-2C7A-4C1B-9E44-0B6F2D1A7C55","role":"protected","text":"画像を見せました","at":0}]}"#
    let log = ChatLog.restored(from: Data(old.utf8), at: Date(timeIntervalSinceReferenceDate: 60))
    #expect(log.messages.map(\.text) == ["画像を見せました"])
    #expect(log.messages.first?.picture == nil)
  }

  // MARK: 残す画像の大きさ

  @Test("残す画像は長い辺を1024ピクセルまでに縮め、送る大きさより小さい")
  func keptSize() {
    let screenshot = PixelSize(width: 1179, height: 2556)
    #expect(ChatPicture.keptSize(of: screenshot) == PixelSize(width: 472, height: 1024))
    #expect(ChatPicture.keptSize(of: PixelSize(width: 4032, height: 3024)) == PixelSize(width: 1024, height: 768))
    #expect(ChatPicture.keptSize(of: PixelSize(width: 800, height: 600)) == PixelSize(width: 800, height: 600))
    let sent = CoordinateMapper.sentSize(of: screenshot)
    #expect(max(sent.width, sent.height) > ChatPicture.maxEdge)
    // 50 of them at most: 15 MB.
    #expect(ChatPicture.maxBytes * ChatLog.keep == 15_000_000)
    #expect(ChatPicture.maxBytes < 2_250_000)
  }
}

/// Pictures in memory, by file name.
final class MemoryPictureStore: ChatPictureStore, @unchecked Sendable {
  var files: [String: Data] = [:]

  func read(_ name: String) throws -> Data? { files[name] }
  func write(_ data: Data, name: String) throws { files[name] = data }
  func remove(_ name: String) throws { files[name] = nil }
  func names() throws -> [String] { Array(files.keys) }
}
