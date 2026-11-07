import Foundation
import Testing

@testable import MimamoriCore

@Suite("声の相談")
struct VoiceConsultTests {
  static let police = ConsultAnswer(
    reply: "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて",
    speak: "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて",
    tap: nil, handoff: true)

  // MARK: API

  @Test("POST /consult に鍵を付けて { text } を送り、答えを読む")
  func sendsConsult() async throws {
    let transport = StubTransport(
      status: 200,
      body: #"{"reply":"設定の「一般」から「iPhone ストレージ」","speak":"設定の一般から iPhone ストレージ","handoff":false}"#)
    let client = APIClient(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))

    let answer = try await client.consult(text: "ストレージがいっぱいと出た")

    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/consult")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    #expect(try bodyJSON(request)["text"] as? String == "ストレージがいっぱいと出た")
    #expect(answer.reply == "設定の「一般」から「iPhone ストレージ」")
    #expect(answer.speak == "設定の一般から iPhone ストレージ")
    #expect(answer.tap == nil)
    #expect(answer.handoff == false)
  }

  @Test("押す場所があれば x と y を読む")
  func readsTap() async throws {
    let transport = StubTransport(
      status: 200, body: #"{"reply":"ここ","speak":"ここ","tap":{"x":540,"y":1210},"handoff":false}"#)
    let client = APIClient(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
    let answer = try await client.consult(text: "どこを押すの")
    #expect(answer.tap == ConsultAnswer.Tap(x: 540, y: 1210))
  }

  @Test("handoff の無い答えは形が違うとして捨てる")
  func rejectsShape() async throws {
    let transport = StubTransport(status: 200, body: #"{"reply":"x","speak":"x"}"#)
    let client = APIClient(
      baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
    await #expect(throws: APIError.invalidResponse) { try await client.consult(text: "x") }
  }

  // MARK: ボタンを押して話す

  @Test("押すと聞き始め、読み上げ中なら止める")
  func tapStartsListening() {
    var flow = VoiceConsult()
    #expect(flow.micTapped(at: .t0) == [.stopSpeaking, .startListening])
    #expect(flow.phase == .listening(heard: ""))
  }

  @Test("聞いている間にもう一度押すと止め、最後の文字を待って送る")
  func secondTapStopsAndSends() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    #expect(flow.heard("警察から電話があって", isFinal: false, at: .t0 + 1).isEmpty)
    #expect(flow.phase == .listening(heard: "警察から電話があって"))
    #expect(flow.micTapped(at: .t0 + 2) == [.stopListening])
    #expect(
      flow.heard("  警察から電話があって、口座が犯罪に使われてるって ", isFinal: true, at: .t0 + 2.2)
        == [.send("警察から電話があって、口座が犯罪に使われてるって")])
    #expect(flow.phase == .thinking(said: "警察から電話があって、口座が犯罪に使われてるって"))
  }

  @Test("答えが来たら画面に出し、読み上げがオンなら読み上げの文を読む")
  func answerIsSpoken() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("警察から電話", isFinal: true, at: .t0 + 1)
    #expect(flow.answered(Self.police, readsAloud: true) == [.speak(Self.police.speak)])
    #expect(flow.phase == .answered(said: "警察から電話", answer: Self.police))
  }

  @Test("考えている間に押しても何もしない(二重に送らない)")
  func tapWhileThinkingIsIgnored() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("相談", isFinal: true, at: .t0 + 1)
    #expect(flow.micTapped(at: .t0 + 2).isEmpty)
    #expect(flow.phase == .thinking(said: "相談"))
  }

  @Test("何も聞き取れなければ送らない")
  func emptyIsNotSent() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    #expect(flow.heard("   ", isFinal: true, at: .t0 + 3).isEmpty)
    #expect(flow.phase == .failed(.notHeard))
  }

  @Test("話し終えて5秒黙ったら自分で止める。まだ何も話していなければ8秒待つ")
  func silenceStops() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    #expect(flow.tick(at: .t0 + 7.9).isEmpty)
    #expect(flow.tick(at: .t0 + 8) == [.stopListening])

    var talking = VoiceConsult()
    _ = talking.micTapped(at: .t0)
    _ = talking.listeningStarted(at: .t0)
    _ = talking.heard("ストレージが", isFinal: false, at: .t0 + 1)
    #expect(talking.tick(at: .t0 + 2.4).isEmpty)
    _ = talking.heard("ストレージがいっぱい", isFinal: false, at: .t0 + 2.5)
    // Two seconds of silence no longer stop it (#224): there is time for stop and trash.
    #expect(talking.tick(at: .t0 + 4.5).isEmpty)
    #expect(talking.tick(at: .t0 + 7.4).isEmpty)
    #expect(talking.tick(at: .t0 + 7.5) == [.stopListening])
    // Asked to stop once; the recognizer's final result comes next.
    #expect(talking.tick(at: .t0 + 8).isEmpty)
  }

  @Test("許可の画面で聞き始めが遅れても、始まるまでは黙っているとみなさない")
  func silenceCountsFromTheStart() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    // The first time, the speech and microphone permission sheets take a while.
    #expect(flow.tick(at: .t0 + 8).isEmpty)
    #expect(flow.tick(at: .t0 + 12).isEmpty)
    #expect(flow.listeningStarted(at: .t0 + 12.5).isEmpty)
    #expect(flow.tick(at: .t0 + 20.4).isEmpty)
    #expect(flow.tick(at: .t0 + 20.5) == [.stopListening])
  }

  @Test("聞き始める前に押されたら、始まった直後に止める。マイクは次も効く")
  func stopBeforeStartIsKept() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    // Nothing is listening yet, so there is nothing to stop now.
    #expect(flow.micTapped(at: .t0 + 3).isEmpty)
    #expect(flow.micTapped(at: .t0 + 4).isEmpty)
    #expect(flow.listeningStarted(at: .t0 + 9) == [.stopListening])
    #expect(flow.tick(at: .t0 + 20).isEmpty)
    // The recognizer ends with nothing heard; the next press listens again.
    #expect(flow.listeningFailed(.notHeard).isEmpty)
    #expect(flow.micTapped(at: .t0 + 21) == [.stopSpeaking, .startListening])
  }

  @Test("1分たったら話していても止める(端末の中の聞き取りの上限)")
  func longTalkStops() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    for second in stride(from: 1.0, to: 60, by: 1) {
      _ = flow.heard(String(repeating: "あ", count: Int(second)), isFinal: false, at: .t0 + second)
    }
    #expect(flow.tick(at: .t0 + 60) == [.stopListening])
  }

  @Test("1,000字を超えた分は送らない(裏側の上限)")
  func longTextIsCut() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    let effects = flow.heard(String(repeating: "あ", count: 1200), isFinal: true, at: .t0 + 1)
    #expect(effects == [.send(String(repeating: "あ", count: 1000))])
  }

  @Test("聞き取りが途中で失敗しても、聞けたところまでは送る")
  func failureAfterWordsSends() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("口座が犯罪に", isFinal: false, at: .t0 + 1)
    #expect(flow.listeningFailed(.unavailable) == [.send("口座が犯罪に")])
  }

  @Test("マイクの許可が無ければ聞かずに止まる")
  func permissionDenied() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    #expect(flow.listeningFailed(.permissionDenied).isEmpty)
    #expect(flow.phase == .failed(.permissionDenied))
  }

  @Test("送れなければ、つながらないと出す。もう一度押せば聞き直す")
  func sendFailure() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("相談", isFinal: true, at: .t0 + 1)
    flow.sendFailed()
    #expect(flow.phase == .failed(.offline))
    #expect(flow.micTapped(at: .t0 + 5) == [.stopSpeaking, .startListening])
  }

  @Test("聞き直し始めたあとに来た古い答えは出さない")
  func staleAnswerIsDropped() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.heard("相談", isFinal: true, at: .t0 + 1)
    flow.sendFailed()
    _ = flow.micTapped(at: .t0 + 2)
    #expect(flow.answered(Self.police).isEmpty)
    #expect(flow.phase == .listening(heard: ""))
  }

  @Test("画面の文字は短い名札だけで、説明は読み上げのラベルにある")
  func labels() {
    for failure in [ConsultFailure.notHeard, .permissionDenied, .unavailable, .offline] {
      #expect(failure.text.count <= 12)
      #expect(failure.accessibilityHint.count > failure.text.count)
    }
    var flow = VoiceConsult()
    #expect(flow.micLabel == "話しかける")
    _ = flow.micTapped(at: .t0)
    #expect(flow.micLabel == "聞いています")
  }

  @Test("どの状態の文字にも「安全」は出ない")
  func neverSafe() {
    let texts =
      [ConsultFailure.notHeard, .permissionDenied, .unavailable, .offline].flatMap {
        [$0.text, $0.accessibilityHint]
      }
      + [VoiceConsult().micLabel, VoiceConsult().micHint]
    for text in texts { #expect(!text.contains("安全")) }
  }
}

@Suite("答えを画面に出しておく")
struct FollowsNoticesTests {
  static let storage = ConsultAnswer(reply: "設定の「一般」から", speak: "設定の一般から", tap: nil, handoff: false)

  @Test("話しているあいだと考えているあいだは、知らせが増えても答えの場所を見せる")
  func whileTalking() {
    #expect(ConsultPhase.listening(heard: "警察から").followsNotices)
    #expect(ConsultPhase.thinking(said: "警察から").followsNotices)
  }

  @Test("家族に回した答えだけ、そのあとの知らせの読み直しについていく")
  func afterAnswer() {
    #expect(ConsultPhase.answered(said: "警察から", answer: VoiceConsultTests.police).followsNotices)
    #expect(!ConsultPhase.answered(said: "ストレージ", answer: Self.storage).followsNotices)
  }

  @Test("何もしていないときと失敗のあとは、知らせが変わっても動かさない")
  func otherwise() {
    #expect(!ConsultPhase.idle.followsNotices)
    #expect(!ConsultPhase.failed(.offline).followsNotices)
  }
}

extension Date {
  static let t0 = Date(timeIntervalSince1970: 1_793_000_000)
}
