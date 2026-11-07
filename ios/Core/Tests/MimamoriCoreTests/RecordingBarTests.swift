import Foundation
import Testing

@testable import MimamoriCore

/// The field while the microphone listens, shaped like the usual chat apps' recording field (#224):
/// trash, elapsed time, dots that follow her voice, stop, send.
@Suite("録音中の欄")
struct RecordingBarTests {
  private static func listening(heard: String? = nil) -> VoiceConsult {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    _ = flow.listeningStarted(at: .t0)
    if let heard { _ = flow.heard(heard, isFinal: false, at: .t0 + 1) }
    return flow
  }

  // MARK: 送る

  @Test("送るを押すと止め、最後の文字を待ってそのまま送る")
  func sendSends() {
    var flow = Self.listening(heard: "警察から電話")
    #expect(flow.sendTapped(at: .t0 + 2) == [.stopListening])
    #expect(flow.heard("警察から電話があった", isFinal: true, at: .t0 + 2.2) == [.send("警察から電話があった")])
    #expect(flow.phase == .thinking(said: "警察から電話があった"))
  }

  @Test("送るで送った答えは、声で聞いた扱いで読み上げの決まりに従う")
  func sendIsVoice() {
    var flow = Self.listening(heard: "警察から")
    _ = flow.sendTapped(at: .t0 + 2)
    _ = flow.heard("警察から", isFinal: true, at: .t0 + 2.1)
    #expect(
      flow.answered(VoiceConsultTests.police, readsAloud: true) == [
        .speak(VoiceConsultTests.police.speak)
      ])
  }

  // MARK: 止める

  @Test("止めるを押すと止め、最後の文字を欄に入れて何も送らない")
  func stopFillsDraft() {
    var flow = Self.listening(heard: "警察から電話")
    #expect(flow.stopTapped(at: .t0 + 2) == [.stopListening])
    #expect(flow.heard(" 警察から電話があった ", isFinal: true, at: .t0 + 2.2) == [.fillDraft("警察から電話があった")])
    #expect(flow.phase == .idle)
    #expect(flow.acceptsText)
  }

  @Test("止めたあとに黙っていても、自分では送らない")
  func stopThenSilenceDoesNotSend() {
    var flow = Self.listening(heard: "警察から")
    _ = flow.stopTapped(at: .t0 + 2)
    #expect(flow.tick(at: .t0 + 10).isEmpty)
    #expect(flow.heard("警察から", isFinal: true, at: .t0 + 10.1) == [.fillDraft("警察から")])
  }

  @Test("止めて欄に入った文を直して送ると、声で聞いた扱いで読み上げる")
  func editedDraftIsVoice() {
    var flow = Self.listening(heard: "警察から")
    _ = flow.stopTapped(at: .t0 + 2)
    _ = flow.heard("警察から", isFinal: true, at: .t0 + 2.1)
    #expect(flow.typed("警察から電話があった", at: .t0 + 9) == [.stopSpeaking, .send("警察から電話があった")])
    #expect(
      flow.answered(VoiceConsultTests.police, readsAloud: true) == [
        .speak(VoiceConsultTests.police.speak)
      ])
  }

  @Test("欄を空にしてから書いて送ると、文字で送った扱いで読み上げない")
  func clearedDraftIsTyped() {
    var flow = Self.listening(heard: "警察から")
    _ = flow.stopTapped(at: .t0 + 2)
    _ = flow.heard("警察から", isFinal: true, at: .t0 + 2.1)
    flow.draftCleared()
    _ = flow.typed("ストレージがいっぱい", at: .t0 + 9)
    #expect(flow.answered(VoiceConsultTests.police, readsAloud: true).isEmpty)
  }

  @Test("欄に声の文があるあいだだけ、それと分かる")
  func hasVoiceDraft() {
    var flow = Self.listening(heard: "警察から")
    #expect(!flow.hasVoiceDraft)
    _ = flow.stopTapped(at: .t0 + 2)
    _ = flow.heard("警察から", isFinal: true, at: .t0 + 2.1)
    #expect(flow.hasVoiceDraft)
    flow.draftCleared()
    #expect(!flow.hasVoiceDraft)
  }

  @Test("声で入れた文の扱いは次の1回だけで、その次に書いて送ったものは読み上げない")
  func voiceDraftIsOnce() {
    var flow = Self.listening(heard: "警察から")
    _ = flow.stopTapped(at: .t0 + 2)
    _ = flow.heard("警察から", isFinal: true, at: .t0 + 2.1)
    _ = flow.typed("警察から", at: .t0 + 3)
    _ = flow.answered(VoiceConsultTests.police, readsAloud: true)
    _ = flow.typed("ありがとう", at: .t0 + 20)
    #expect(flow.answered(VoiceConsultTests.police, readsAloud: true).isEmpty)
  }

  @Test("止めて何も聞き取れていなければ、欄に何も入れず聞き取れなかったと出す")
  func stopWithNothing() {
    var flow = Self.listening()
    _ = flow.stopTapped(at: .t0 + 2)
    #expect(flow.heard("  ", isFinal: true, at: .t0 + 2.1).isEmpty)
    #expect(flow.phase == .failed(.notHeard))
  }

  @Test("止めたあとに聞き取りが失敗しても、聞けたところまでは欄に入れる")
  func stopThenFailureFills() {
    var flow = Self.listening(heard: "口座が")
    _ = flow.stopTapped(at: .t0 + 2)
    #expect(flow.listeningFailed(.notHeard) == [.fillDraft("口座が")])
    #expect(flow.phase == .idle)
  }

  @Test("聞き始める前に止めるを押したら、始まった直後に止めて欄に入れる")
  func stopBeforeStart() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    #expect(flow.stopTapped(at: .t0 + 1).isEmpty)
    #expect(flow.listeningStarted(at: .t0 + 5) == [.stopListening])
    #expect(flow.heard("警察", isFinal: true, at: .t0 + 5.5) == [.fillDraft("警察")])
  }

  // MARK: ゴミ箱

  @Test("ゴミ箱を押すとすぐやめ、何も送らず、あとから来た文字も捨てる")
  func discardDropsEverything() {
    var flow = Self.listening(heard: "警察から")
    #expect(flow.discardTapped() == [.cancelListening])
    #expect(flow.phase == .idle)
    #expect(flow.heard("警察から電話", isFinal: true, at: .t0 + 3).isEmpty)
    #expect(flow.listeningFailed(.notHeard).isEmpty)
    #expect(flow.phase == .idle)
    #expect(flow.tick(at: .t0 + 30).isEmpty)
  }

  @Test("送るを押したあとでも、最後の文字が来る前ならゴミ箱で捨てられる")
  func discardAfterSend() {
    var flow = Self.listening(heard: "警察から")
    _ = flow.sendTapped(at: .t0 + 2)
    #expect(flow.discardTapped() == [.cancelListening])
    #expect(flow.heard("警察から", isFinal: true, at: .t0 + 2.1).isEmpty)
    #expect(flow.phase == .idle)
  }

  @Test("聞き始める前でもゴミ箱でやめられ、次のマイクはまた聞く")
  func discardBeforeStart() {
    var flow = VoiceConsult()
    _ = flow.micTapped(at: .t0)
    #expect(flow.discardTapped() == [.cancelListening])
    #expect(flow.listeningStarted(at: .t0 + 3).isEmpty)
    #expect(flow.micTapped(at: .t0 + 4) == [.stopSpeaking, .startListening])
  }

  @Test("聞いていないときのゴミ箱、止める、送るは何もしない")
  func buttonsOutsideListening() {
    var flow = VoiceConsult()
    #expect(flow.discardTapped().isEmpty)
    #expect(flow.stopTapped(at: .t0).isEmpty)
    #expect(flow.sendTapped(at: .t0).isEmpty)
    #expect(flow.phase == .idle)
  }

  // MARK: 無音

  @Test("話し終えて黙ったら、今までどおり自分で止めて送る")
  func silenceStillSends() {
    var flow = Self.listening(heard: "ストレージがいっぱい")
    #expect(flow.tick(at: .t0 + 5.9).isEmpty)
    #expect(flow.tick(at: .t0 + 6) == [.stopListening])
    #expect(flow.heard("ストレージがいっぱい", isFinal: true, at: .t0 + 6.1) == [.send("ストレージがいっぱい")])
  }

  // MARK: 経過時間

  @Test("経過時間は聞き始めから数え、許可の画面のあいだは無い")
  func listeningSince() {
    var flow = VoiceConsult()
    #expect(flow.listeningSince == nil)
    _ = flow.micTapped(at: .t0)
    #expect(flow.listeningSince == nil)
    _ = flow.listeningStarted(at: .t0 + 4)
    #expect(flow.listeningSince == .t0 + 4)
    _ = flow.discardTapped()
    #expect(flow.listeningSince == nil)
  }

  @Test("経過時間は分:秒で、秒は2桁")
  func clockText() {
    #expect(RecordingClock.text(elapsed: 0) == "0:00")
    #expect(RecordingClock.text(elapsed: 5.9) == "0:05")
    #expect(RecordingClock.text(elapsed: 59.99) == "0:59")
    #expect(RecordingClock.text(elapsed: 60) == "1:00")
    #expect(RecordingClock.text(elapsed: 62) == "1:02")
    #expect(RecordingClock.text(elapsed: 600) == "10:00")
    #expect(RecordingClock.text(elapsed: -3) == "0:00")
  }

  @Test("経過時間の読み上げは秒と分の言葉")
  func clockSpoken() {
    #expect(RecordingClock.spoken(elapsed: 5) == "5秒")
    #expect(RecordingClock.spoken(elapsed: 60) == "1分")
    #expect(RecordingClock.spoken(elapsed: 62) == "1分2秒")
  }

  // MARK: 声の大きさ

  @Test("音の強さは -50dB から 0dB を 0 から 1 にし、外は端にそろえる")
  func normalized() {
    #expect(VoiceLevels.normalized(rms: 0) == 0)
    #expect(VoiceLevels.normalized(rms: 0.000_01) == 0)
    #expect(VoiceLevels.normalized(rms: 1) == 1)
    #expect(VoiceLevels.normalized(rms: 2) == 1)
    let quiet = VoiceLevels.normalized(rms: 0.01)
    let loud = VoiceLevels.normalized(rms: 0.1)
    #expect(quiet > 0 && quiet < loud && loud < 1)
    #expect(abs(VoiceLevels.normalized(rms: 0.1) - 0.6) < 0.001)
  }

  @Test("点の数は決まっていて、新しい音が右に入り、古い音が左から抜ける")
  func ring() {
    var levels = VoiceLevels(count: 4)
    #expect(levels.values == [0, 0, 0, 0])
    levels.add(rms: 1)
    #expect(levels.values == [0, 0, 0, 1])
    levels.add(rms: 0)
    levels.add(rms: 1)
    levels.add(rms: 1)
    levels.add(rms: 0)
    #expect(levels.values == [0, 1, 1, 0])
    #expect(levels.values.count == 4)
  }

  @Test("やめると点は全部静かに戻る")
  func reset() {
    var levels = VoiceLevels(count: 3)
    levels.add(rms: 1)
    levels.reset()
    #expect(levels.values == [0, 0, 0])
  }

  // MARK: 文字

  @Test("ボタンに文字の名札は無く、読み上げに説明がある。「安全」は出ない")
  func labels() {
    let texts = [
      RecordingBar.discardLabel, RecordingBar.discardHint, RecordingBar.stopLabel,
      RecordingBar.stopHint,
      RecordingBar.sendLabel, RecordingBar.sendHint, RecordingBar.levelsLabel,
    ]
    for text in texts {
      #expect(!text.isEmpty)
      #expect(!text.contains("安全"))
    }
    #expect(RecordingBar.discardHint.contains("送りません"))
  }
}
