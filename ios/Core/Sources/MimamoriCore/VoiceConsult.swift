import Foundation

// The protected person's consultation ("スマホ相談と声" in docs/design.md): press the microphone
// and talk, or type and send, and the answer appears in her chat (Chat.swift). An answer is read
// aloud only when 「読み上げ」 is on in Settings (off by default, #115) and she asked by voice, so a
// typed question never makes the phone speak in public (#73). The App's adapters do the listening
// (Speech, on the device), the sending (POST /consult), and the speaking (AVSpeechSynthesizer); every
// decision about what happens next is here so it can be tested.

/// `POST /consult` answers `{ reply, speak, tap?, handoff }` (docs/plan.md).
public struct ConsultAnswer: Decodable, Equatable, Sendable {
  public struct Tap: Decodable, Equatable, Sendable {
    /// Pixels in the screenshot that was sent.
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  /// Shown on the screen.
  public let reply: String
  /// Read aloud.
  public let speak: String
  public let tap: Tap?
  /// The family was told and will take it from here.
  public let handoff: Bool

  public init(reply: String, speak: String, tap: Tap?, handoff: Bool) {
    self.reply = reply
    self.speak = speak
    self.tap = tap
    self.handoff = handoff
  }
}

/// Why a consultation stopped before an answer. `text` is the short tag on the screen; the
/// explanation is for VoiceOver.
public enum ConsultFailure: Equatable, Sendable {
  case notHeard
  case permissionDenied
  /// The recognizer is not available (no Japanese on-device model, or it failed).
  case unavailable
  /// The answer could not be fetched.
  case offline
  /// The image she picked with the photo button could not be read or made small enough (#221).
  case unreadableImage

  public var text: String {
    switch self {
    case .notHeard: "聞き取れませんでした"
    case .permissionDenied: "マイクの許可"
    case .unavailable: "聞き取れません"
    case .offline: "つながりません"
    case .unreadableImage: "画像を読めません"
    }
  }

  public var accessibilityHint: String {
    switch self {
    case .notHeard: "声が聞き取れませんでした。もう一度マイクを押して、ゆっくり話してください"
    case .permissionDenied: "マイクと音声認識の許可がありません。設定アプリで mimamori のマイクと音声認識をオンにしてください"
    case .unavailable: "この iPhone では今、声を文字にできません。少し待ってからもう一度押すか、家族に電話してください"
    case .offline: "インターネットにつながらず、答えを受け取れませんでした。もう一度押すか、家族に電話してください"
    case .unreadableImage: "選んだ画像を読めず、送りませんでした。別のスクショを選ぶか、困っていることを書いて送ってください"
    }
  }
}

public enum ConsultPhase: Equatable, Sendable {
  case idle
  case listening(heard: String)
  case thinking(said: String)
  case answered(said: String, answer: ConsultAnswer)
  case failed(ConsultFailure)

  /// Whether a change in her notices should bring the answer's place back into view: while she talks
  /// and waits, and after an answer only when it went to the family (its notice is still to come).
  /// Otherwise a later change, like the 30-minute line, would pull an old answer back up.
  public var followsNotices: Bool {
    switch self {
    case .idle, .failed: false
    case .listening, .thinking: true
    case .answered(_, let answer): answer.handoff
    }
  }
}

/// What the App's adapters do next.
public enum ConsultEffect: Equatable, Sendable {
  case startListening
  case stopListening
  case send(String)
  /// Put her words into the field, for her to fix and send (the stop button in the recording field, #224).
  case fillDraft(String)
  /// Drop everything heard and stop the microphone at once (the trash button, #224). Nothing is sent.
  case cancelListening
  /// Send the picked image with these words (empty when she wrote none). The image itself stays with
  /// the App's adapter; nothing of it is in here.
  case sendPicture(text: String)
  case speak(String)
  case stopSpeaking
}

public struct VoiceConsult: Sendable {
  public private(set) var phase: ConsultPhase = .idle
  /// When the recognizer actually started. Nil while the permission sheets are still up.
  private var startedAt: Date?
  private var lastHeardAt: Date?
  /// How listening was asked to end: nil while it goes on.
  private var ending: Ending?
  /// She pressed before listening started: end this way as soon as it starts.
  private var pendingEnding: Ending?
  /// This consultation came by voice, so its answer is read aloud when 「読み上げ」 is on.
  private var byVoice = false
  /// The field holds words she said and stopped with the stop button. Sent, they count as asked by
  /// voice (they came from her voice, she only fixed them); emptying the field ends that (#224).
  private var voiceDraft = false

  /// What happens to her words once the recognizer hands over the last of them.
  private enum Ending {
    /// The send button, a second press of the microphone, silence, and the one-minute limit.
    case send
    /// The stop button: into the field.
    case draft
  }

  /// The server refuses longer text (server/src/consult.ts, CONSULT_TEXT_MAX_CHARS).
  public static let maxCharacters = 1000
  /// After she stops talking for this long, listening ends by itself, so she need not press again.
  public static let silenceAfterWords: TimeInterval = 2
  /// When nothing at all is heard.
  public static let silenceBeforeWords: TimeInterval = 8
  /// On-device recognition is for short requests; a minute is plenty for one question.
  public static let longest: TimeInterval = 60

  public init() {}

  /// The microphone. Starts listening, or ends it; ignored while an answer is coming.
  public mutating func micTapped(at now: Date) -> [ConsultEffect] {
    switch phase {
    case .idle, .answered, .failed:
      phase = .listening(heard: "")
      startedAt = nil
      lastHeardAt = nil
      ending = nil
      pendingEnding = nil
      byVoice = true
      voiceDraft = false
      return [.stopSpeaking, .startListening]
    case .listening:
      return requestEnd(.send)
    case .thinking:
      return []
    }
  }

  /// The send button in the recording field: her words go as they are, as by voice.
  public mutating func sendTapped(at now: Date) -> [ConsultEffect] {
    guard case .listening = phase else { return [] }
    return requestEnd(.send)
  }

  /// The stop button in the recording field: her words go into the field, and nothing is sent.
  public mutating func stopTapped(at now: Date) -> [ConsultEffect] {
    guard case .listening = phase else { return [] }
    return requestEnd(.draft)
  }

  /// The trash button in the recording field: listening ends now and nothing heard is kept or sent.
  /// Words the recognizer hands over later are dropped (`heard` and `listeningFailed` ignore them).
  public mutating func discardTapped() -> [ConsultEffect] {
    guard case .listening = phase else { return [] }
    phase = .idle
    startedAt = nil
    lastHeardAt = nil
    ending = nil
    pendingEnding = nil
    byVoice = false
    return [.cancelListening]
  }

  /// The field holds her words from the stop button, so sending them counts as by voice.
  public var hasVoiceDraft: Bool { voiceDraft }

  /// She emptied the field: what she writes next is typed, not said.
  public mutating func draftCleared() {
    voiceDraft = false
  }

  /// When the recognizer started, while it listens: the recording field's clock counts from here.
  /// Nil while the permission sheets are still up, and once listening ended.
  public var listeningSince: Date? {
    guard case .listening = phase else { return nil }
    return startedAt
  }

  /// Whether written words can be sent now: not while listening or waiting for an answer.
  public var acceptsText: Bool {
    switch phase {
    case .idle, .answered, .failed: true
    case .listening, .thinking: false
    }
  }

  /// She typed and pressed send. Sent as it is (trimmed, at most `maxCharacters`); never read aloud.
  public mutating func typed(_ text: String, at now: Date) -> [ConsultEffect] {
    guard acceptsText else { return [] }
    let said = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxCharacters))
    guard !said.isEmpty else { return [] }
    byVoice = voiceDraft
    voiceDraft = false
    phase = .thinking(said: said)
    return [.stopSpeaking, .send(said)]
  }

  /// Her line in the conversation for a screenshot she showed with the photo button (#221). The image
  /// is never kept, so this and the answer are all the conversation holds of it.
  public static let pictureLine = "画像を見せました"

  /// She picked an image with the photo button, with whatever is in the field. Her line is
  /// `pictureLine`, followed by her words when there are any. Never read aloud, like typed words.
  public mutating func pictured(_ text: String, at now: Date) -> [ConsultEffect] {
    guard acceptsText else { return [] }
    let words = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxCharacters))
    byVoice = false
    voiceDraft = false
    phase = .thinking(said: words.isEmpty ? Self.pictureLine : "\(Self.pictureLine)。\(words)")
    return [.stopSpeaking, .sendPicture(text: words)]
  }

  /// The picked image could not be read; nothing was sent and nothing joins the conversation.
  public mutating func pictureUnreadable() {
    guard acceptsText else { return }
    phase = .failed(.unreadableImage)
  }

  /// The recognizer is listening. The first time, this comes after the permission sheets, so the
  /// silence clock starts here, not at the press. A press that came before is carried out now.
  public mutating func listeningStarted(at now: Date) -> [ConsultEffect] {
    guard case .listening = phase, startedAt == nil else { return [] }
    startedAt = now
    return pendingEnding.map { requestEnd($0) } ?? []
  }

  /// What the recognizer has so far. The final result sends it.
  public mutating func heard(_ text: String, isFinal: Bool, at now: Date) -> [ConsultEffect] {
    guard case .listening = phase else { return [] }
    if !isFinal {
      phase = .listening(heard: text)
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastHeardAt = now }
      return []
    }
    return finish(with: text)
  }

  /// Called about every half second while listening, to stop on silence or after a minute.
  public mutating func tick(at now: Date) -> [ConsultEffect] {
    guard case .listening = phase, ending == nil, let startedAt else { return [] }
    if now.timeIntervalSince(startedAt) >= Self.longest { return requestEnd(.send) }
    if let lastHeardAt {
      if now.timeIntervalSince(lastHeardAt) >= Self.silenceAfterWords { return requestEnd(.send) }
    } else if now.timeIntervalSince(startedAt) >= Self.silenceBeforeWords {
      return requestEnd(.send)
    }
    return []
  }

  /// Listening could not start or broke off. What was already heard is still sent (or, after the
  /// stop button, put into the field).
  public mutating func listeningFailed(_ failure: ConsultFailure) -> [ConsultEffect] {
    guard case .listening(let heard) = phase else { return [] }
    if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return finish(with: heard) }
    phase = .failed(failure)
    return []
  }

  /// The answer arrived. Dropped when she has already started again. Read aloud only when
  /// `readsAloud` (「読み上げ」 in Settings, `ReadAloudSettings`) is on and she asked by voice.
  public mutating func answered(_ answer: ConsultAnswer, readsAloud: Bool = ReadAloudSettings.standard.isOn)
    -> [ConsultEffect]
  {
    guard case .thinking(let said) = phase else { return [] }
    phase = .answered(said: said, answer: answer)
    return readsAloud && byVoice ? [.speak(answer.speak)] : []
  }

  public mutating func sendFailed() {
    guard case .thinking = phase else { return }
    phase = .failed(.offline)
  }

  /// Before the recognizer starts there is nothing to stop yet, so the press waits for it (the latest
  /// press wins). After, the first way asked is kept.
  private mutating func requestEnd(_ way: Ending) -> [ConsultEffect] {
    guard startedAt != nil else {
      pendingEnding = way
      return []
    }
    guard ending == nil else { return [] }
    ending = way
    return [.stopListening]
  }

  private mutating func finish(with text: String) -> [ConsultEffect] {
    let said = String(
      text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxCharacters))
    guard !said.isEmpty else {
      phase = .failed(.notHeard)
      return []
    }
    if ending == .draft {
      phase = .idle
      voiceDraft = true
      return [.fillDraft(said)]
    }
    phase = .thinking(said: said)
    return [.send(said)]
  }

  /// The microphone's VoiceOver label. The button itself shows only the icon.
  public var micLabel: String {
    switch phase {
    case .listening: "聞いています"
    case .thinking: "考えています"
    default: "話しかける"
    }
  }

  public var micHint: String {
    switch phase {
    case .listening: "話し終わると自動で送ります"
    case .thinking: "答えを待っています"
    default: "押して話すと、スマホの困りごとや気になる電話について答えます"
    }
  }
}
