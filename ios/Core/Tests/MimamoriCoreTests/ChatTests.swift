import Foundation
import Testing

@testable import MimamoriCore

// #73: her screen is a chat. What she said and what the AI answered stay on her iPhone (the newest
// 50), and the turns of the same conversation go along with the next consultation.

@Suite("会話の並び")
struct ChatLogTests {
  @Test("足した順に古いものから並ぶ")
  func appendsInOrder() {
    var log = ChatLog()
    log.append(.protected, "ストレージがいっぱいと出た", at: .t0)
    log.append(.ai, "設定の「一般」から", at: .t0 + 3)
    #expect(log.messages.map(\.role) == [.protected, .ai])
    #expect(log.messages.map(\.text) == ["ストレージがいっぱいと出た", "設定の「一般」から"])
    #expect(log.messages.map(\.at) == [.t0, .t0 + 3])
    #expect(Set(log.messages.map(\.id)).count == 2)
  }

  @Test("50件を超えたら古いものから落とす")
  func keepsTheNewest50() {
    var log = ChatLog()
    for i in 0..<53 { log.append(i % 2 == 0 ? .protected : .ai, "話\(i)", at: .t0 + Double(i)) }
    #expect(ChatLog.keep == 50)
    #expect(log.messages.count == 50)
    #expect(log.messages.first?.text == "話3")
    #expect(log.messages.last?.text == "話52")
  }

  @Test("保存した形から同じ並びに戻る")
  func roundTrip() throws {
    var log = ChatLog()
    log.append(.protected, "警察から電話があって", at: .t0)
    log.append(.ai, "詐欺で使われる説明と一致しています。", at: .t0 + 2)
    let restored = ChatLog.restored(from: try log.encoded())
    #expect(restored == log)
  }

  @Test("ファイルが無いか壊れていれば空から始める")
  func restoresEmpty() {
    #expect(ChatLog.restored(from: nil).messages.isEmpty)
    #expect(ChatLog.restored(from: Data("not json".utf8)).messages.isEmpty)
  }

  @Test("壊れた形でも51件以上なら新しい50件にする")
  func restoredIsCapped() throws {
    let many = (0..<60).map {
      ChatMessage(id: UUID(), role: .protected, text: "話\($0)", at: .t0 + Double($0))
    }
    let data = try JSONEncoder().encode(["messages": many])
    let restored = ChatLog.restored(from: data)
    #expect(restored.messages.count == 50)
    #expect(restored.messages.first?.text == "話10")
  }
}

@Suite("裏側に渡す前のやり取り")
struct ChatHistoryTests {
  @Test("同じ会話(60分)の中だけを渡し、それより前は落とす")
  func dropsOlderThanAnHour() {
    var log = ChatLog()
    log.append(.protected, "昨日のこと", at: .t0)
    log.append(.ai, "昨日の答え", at: .t0 + 10)
    log.append(.protected, "警察から電話があって", at: .t0 + 3600)
    log.append(.ai, "詐欺で使われる説明と一致しています。", at: .t0 + 3605)
    // 59 minutes after the second pair: in. The first pair is two hours old: out.
    let now = Date.t0 + 3600 + 60 * 59
    #expect(
      log.history(at: now) == [
        ConsultTurn(role: .protected, text: "警察から電話があって"),
        ConsultTurn(role: .ai, text: "詐欺で使われる説明と一致しています。"),
      ])
    // 60 minutes and 4 seconds after her words, 59 minutes and 59 seconds after the answer.
    #expect(log.history(at: .t0 + 3600 + 3604).map(\.text) == ["詐欺で使われる説明と一致しています。"])
    // Exactly 60 minutes is no longer the same conversation.
    #expect(log.history(at: .t0 + 3605 + 3600).isEmpty)
    #expect(log.history(at: .t0 + 3600 * 3).isEmpty)
  }

  @Test("渡すのは直前の6件まで")
  func lastSix() {
    var log = ChatLog()
    for i in 0..<9 { log.append(i % 2 == 0 ? .protected : .ai, "話\(i)", at: .t0 + Double(i)) }
    let history = log.history(at: .t0 + 10)
    #expect(ChatLog.historyTurns == 6)
    #expect(history.map(\.text) == ["話3", "話4", "話5", "話6", "話7", "話8"])
    #expect(history.map(\.role) == [.ai, .protected, .ai, .protected, .ai, .protected])
  }

  @Test("1件は500字で切る。裏側と同じく文字のコードで数える")
  func cutsAt500() {
    var log = ChatLog()
    log.append(.protected, String(repeating: "あ", count: 600), at: .t0)
    // An emoji with a skin tone is one character on the screen but two code points on the server.
    log.append(.ai, String(repeating: "👍🏽", count: 300), at: .t0 + 1)
    let history = log.history(at: .t0 + 2)
    #expect(ChatLog.turnMaxCharacters == 500)
    #expect(history[0].text == String(repeating: "あ", count: 500))
    #expect(history[1].text.unicodeScalars.count == 500)
  }

  @Test("裏側の形 { role, text } で送る")
  func encodesForTheServer() throws {
    let data = try JSONEncoder().encode(ConsultTurn(role: .protected, text: "警察から"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
    #expect(json == ["role": "protected", "text": "警察から"])
    let ai = try JSONEncoder().encode(ConsultTurn(role: .ai, text: "x"))
    #expect(String(decoding: ai, as: UTF8.self).contains(#""role":"ai""#))
  }
}

/// A store that can be locked, like a file under NSFileProtectionComplete before the first unlock.
final class MemoryChatStore: ChatLogStore, @unchecked Sendable {
  var data: Data?
  var locked = false
  var saves = 0

  init(_ data: Data? = nil) { self.data = data }

  struct Locked: Error {}

  func read() throws -> Data? {
    if locked { throw Locked() }
    return data
  }

  func write(_ data: Data) throws {
    if locked { throw Locked() }
    self.data = data
    saves += 1
  }
}

@Suite("履歴を端末に残す")
struct ChatKeeperTests {
  @Test("相談を送る前のやり取りを渡してから、今の言葉を足して残す")
  func sendGivesTheEarlierTurns() {
    let store = MemoryChatStore()
    var keeper = ChatKeeper(store: store)
    keeper.load()
    #expect(keeper.send("ストレージがいっぱいと出た", at: .t0).isEmpty)
    keeper.answered("設定の「一般」から", at: .t0 + 3)
    let history = keeper.send("それってどういうこと?", at: .t0 + 60)
    #expect(history.map(\.text) == ["ストレージがいっぱいと出た", "設定の「一般」から"])
    #expect(keeper.log.messages.last?.text == "それってどういうこと?")
    #expect(store.saves == 3)
  }

  @Test("残したものを開き直すと読み戻せる")
  func reloads() {
    let store = MemoryChatStore()
    var first = ChatKeeper(store: store)
    first.load()
    _ = first.send("警察から電話があって", at: .t0)
    first.answered("詐欺で使われる説明と一致しています。", at: .t0 + 2)

    var again = ChatKeeper(store: store)
    again.load()
    #expect(again.log == first.log)
  }

  @Test("読めないあいだ(画面のロック中)は、残っている履歴を空で上書きしない")
  func doesNotOverwriteWhileLocked() throws {
    var saved = ChatLog()
    saved.append(.protected, "前の相談", at: .t0)
    let store = MemoryChatStore(try saved.encoded())
    store.locked = true
    var keeper = ChatKeeper(store: store)
    keeper.load()
    #expect(!keeper.isLoaded)

    // Unlocked again: the next send reads the file first, so nothing is lost.
    store.locked = false
    _ = keeper.send("それってどういうこと?", at: .t0 + 60)
    #expect(keeper.log.messages.map(\.text) == ["前の相談", "それってどういうこと?"])
    #expect(ChatLog.restored(from: store.data).messages.count == 2)
  }

  @Test("読めないまま送っても、ファイルには書かない")
  func keepsInMemoryWhileLocked() throws {
    var saved = ChatLog()
    saved.append(.protected, "前の相談", at: .t0)
    let before = try saved.encoded()
    let store = MemoryChatStore(before)
    store.locked = true
    var keeper = ChatKeeper(store: store)
    _ = keeper.send("いま", at: .t0 + 60)
    #expect(store.saves == 0)
    #expect(store.data == before)
    #expect(keeper.log.messages.map(\.text) == ["いま"])
  }
}

@Suite("声と文字で読み上げるかどうか")
struct SpeakOnlyByVoiceTests {
  static let answer = ConsultAnswer(reply: "設定の「一般」から", speak: "設定の一般から", tap: nil, handoff: false)

  @Test("声で聞いたときは答えを読み上げる")
  func voiceIsSpoken() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("ストレージがいっぱい", isFinal: true, at: .t0 + 1)
    #expect(flow.answered(Self.answer) == [.speak("設定の一般から")])
  }

  @Test("文字で聞いたときは読み上げない(人前で急に声が出ないように)")
  func typedIsNotSpoken() {
    var flow = VoiceConsult()
    #expect(flow.typed("  ストレージがいっぱい ", at: .t0) == [.stopSpeaking, .send("ストレージがいっぱい")])
    #expect(flow.phase == .thinking(said: "ストレージがいっぱい"))
    #expect(flow.answered(Self.answer).isEmpty)
    #expect(flow.phase == .answered(said: "ストレージがいっぱい", answer: Self.answer))
  }

  @Test("文字で聞いたあとに声で聞けば、また読み上げる")
  func voiceAfterTyped() {
    var flow = VoiceConsult()
    _ = flow.typed("ストレージ", at: .t0)
    _ = flow.answered(Self.answer)
    _ = flow.micTapped(at: .t0 + 5)
    _ = flow.heard("それってどういうこと", isFinal: true, at: .t0 + 6)
    #expect(flow.answered(Self.answer) == [.speak("設定の一般から")])
  }

  @Test("聞いているあいだと考えているあいだは文字を送らない")
  func typedWhileBusyIsIgnored() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    #expect(!flow.acceptsText)
    #expect(flow.typed("x", at: .t0 + 1).isEmpty)
    _ = flow.heard("相談", isFinal: true, at: .t0 + 2)
    #expect(!flow.acceptsText)
    #expect(flow.typed("x", at: .t0 + 3).isEmpty)
    #expect(flow.phase == .thinking(said: "相談"))
    _ = flow.answered(Self.answer)
    #expect(flow.acceptsText)
  }

  @Test("空の文字は送らない。1,000字を超えた分も送らない")
  func typedLimits() {
    var flow = VoiceConsult()
    #expect(flow.typed("   ", at: .t0).isEmpty)
    #expect(flow.phase == .idle)
    #expect(
      flow.typed(String(repeating: "あ", count: 1200), at: .t0) == [
        .stopSpeaking, .send(String(repeating: "あ", count: 1000)),
      ])
  }
}

@Suite("前のやり取りを送る")
struct ConsultHistoryAPITests {
  @Test("前のやり取りがあれば history として送る")
  func sendsHistory() async throws {
    let transport = StubTransport(status: 200, body: #"{"reply":"x","speak":"x","handoff":false}"#)
    let client = APIClient(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
    _ = try await client.consult(
      text: "それってどういうこと?",
      history: [
        ConsultTurn(role: .protected, text: "警察から電話"),
        ConsultTurn(role: .ai, text: "詐欺で使われる説明と一致しています。"),
      ])
    let body = try bodyJSON(try #require(transport.requests.first))
    #expect(body["text"] as? String == "それってどういうこと?")
    let history = try #require(body["history"] as? [[String: String]])
    #expect(
      history == [
        ["role": "protected", "text": "警察から電話"], ["role": "ai", "text": "詐欺で使われる説明と一致しています。"],
      ])
  }

  @Test("前のやり取りが無ければ history を付けない")
  func omitsEmptyHistory() async throws {
    let transport = StubTransport(status: 200, body: #"{"reply":"x","speak":"x","handoff":false}"#)
    let client = APIClient(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
    _ = try await client.consult(text: "相談", history: [])
    #expect(try bodyJSON(try #require(transport.requests.first))["history"] == nil)
  }
}
