import Foundation

// The protected person's consultation ("スマホ相談と声" in docs/design.md): press the microphone
// and talk, or type and send, and the answer appears in her chat (Chat.swift). An answer is read
// aloud only when she asked by voice, so a typed question never makes the phone speak in public (#73). The App's adapters do the listening
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

  public var text: String {
    switch self {
    case .notHeard: "聞き取れませんでした"
    case .permissionDenied: "マイクの許可"
    case .unavailable: "聞き取れません"
    case .offline: "つながりません"
    }
  }

  public var accessibilityHint: String {
    switch self {
    case .notHeard: "声が聞き取れませんでした。もう一度マイクを押して、ゆっくり話してください"
    case .permissionDenied: "マイクと音声認識の許可がありません。設定アプリで mimamori のマイクと音声認識をオンにしてください"
    case .unavailable: "この iPhone では今、声を文字にできません。少し待ってからもう一度押すか、家族に電話してください"
    case .offline: "インターネットにつながらず、答えを受け取れませんでした。もう一度押すか、家族に電話してください"
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
  case speak(String)
  case stopSpeaking
}

public struct VoiceConsult: Sendable {
  public private(set) var phase: ConsultPhase = .idle
  /// When the recognizer actually started. Nil while the permission sheets are still up.
  private var startedAt: Date?
  private var lastHeardAt: Date?
  private var stopRequested = false
  /// She pressed again before listening started: stop as soon as it starts.
  private var stopPending = false
  /// This consultation came by voice, so its answer is read aloud.
  private var byVoice = false

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
      stopRequested = false
      stopPending = false
      byVoice = true
      return [.stopSpeaking, .startListening]
    case .listening:
      guard startedAt != nil else {
        stopPending = true
        return []
      }
      return requestStop()
    case .thinking:
      return []
    }
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
    byVoice = false
    phase = .thinking(said: said)
    return [.stopSpeaking, .send(said)]
  }

  /// The recognizer is listening. The first time, this comes after the permission sheets, so the
  /// silence clock starts here, not at the press. A press that came before is carried out now.
  public mutating func listeningStarted(at now: Date) -> [ConsultEffect] {
    guard case .listening = phase, startedAt == nil else { return [] }
    startedAt = now
    return stopPending ? requestStop() : []
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
    guard case .listening = phase, !stopRequested, let startedAt else { return [] }
    if now.timeIntervalSince(startedAt) >= Self.longest { return requestStop() }
    if let lastHeardAt {
      if now.timeIntervalSince(lastHeardAt) >= Self.silenceAfterWords { return requestStop() }
    } else if now.timeIntervalSince(startedAt) >= Self.silenceBeforeWords {
      return requestStop()
    }
    return []
  }

  /// Listening could not start or broke off. What was already heard is still sent.
  public mutating func listeningFailed(_ failure: ConsultFailure) -> [ConsultEffect] {
    guard case .listening(let heard) = phase else { return [] }
    if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return finish(with: heard) }
    phase = .failed(failure)
    return []
  }

  /// The answer arrived. Dropped when she has already started again.
  public mutating func answered(_ answer: ConsultAnswer) -> [ConsultEffect] {
    guard case .thinking(let said) = phase else { return [] }
    phase = .answered(said: said, answer: answer)
    return byVoice ? [.speak(answer.speak)] : []
  }

  public mutating func sendFailed() {
    guard case .thinking = phase else { return }
    phase = .failed(.offline)
  }

  private mutating func requestStop() -> [ConsultEffect] {
    guard !stopRequested else { return [] }
    stopRequested = true
    return [.stopListening]
  }

  private mutating func finish(with text: String) -> [ConsultEffect] {
    let said = String(
      text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxCharacters))
    guard !said.isEmpty else {
      phase = .failed(.notHeard)
      return []
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
    case .listening: "話し終わると自動で止まります。もう一度押しても止まります"
    case .thinking: "答えを待っています"
    default: "押して話すと、スマホの困りごとや気になる電話について答えます"
    }
  }
}
