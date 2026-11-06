import Foundation

// The protected person's screen is a chat (#73, decided by the author on 2026-11-04): what she said,
// by voice or in writing, on the right, and the AI's answers on the left, oldest first. The
// conversation stays on her iPhone only (the newest `keep`), and the turns of the same conversation
// go with her next consultation so "それってどういうこと?" can be answered, the day after too (#118).
// The server keeps none of it.
// The App's adapter reads and writes the file (NSFileProtectionComplete); everything else is here.

public enum ChatRole: String, Codable, Equatable, Sendable {
  case protected
  case ai
}

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let role: ChatRole
  public let text: String
  /// When it was said or answered. Every message the app writes has it. A record read without one
  /// still decodes, so the rest of the file is kept, and is then dropped like one 30 days old (#113).
  public let at: Date?

  public init(id: UUID, role: ChatRole, text: String, at: Date?) {
    self.id = id
    self.role = role
    self.text = text
    self.at = at
  }
}

/// The time a message was sent as the screen shows it ("14:55") and as VoiceOver reads it ("14時55分").
public struct ChatStamp: Equatable, Sendable {
  public let text: String
  public let spoken: String

  public init(text: String, spoken: String) {
    self.text = text
    self.spoken = spoken
  }
}

/// One row of her chat: a date where the day changes, or a message with its time.
public enum ChatRow: Equatable, Identifiable, Sendable {
  case day(label: String, id: String)
  case message(ChatMessage, time: ChatStamp?)

  public var id: String {
    switch self {
    case .day(_, let id): id
    case .message(let message, _): message.id.uuidString
    }
  }
}

/// One earlier turn as `POST /consult` takes it in `history` (docs/plan.md).
public struct ConsultTurn: Encodable, Equatable, Sendable {
  public let role: ChatRole
  public let text: String

  public init(role: ChatRole, text: String) {
    self.role = role
    self.text = text
  }
}

public struct ChatLog: Codable, Equatable, Sendable {
  public private(set) var messages: [ChatMessage] = []

  /// What stays on the iPhone: the newest this many,
  public static let keep = 50
  /// and none older than this, like her consultations on the server (30 days, docs/design.md).
  public static let keptFor: TimeInterval = 30 * 24 * 60 * 60
  /// The same conversation as the server's (CONVERSATION_WINDOW_MS in server/src/consult.ts).
  public static let window: TimeInterval = 60 * 60
  /// The server refuses more (HISTORY_MAX_TURNS, HISTORY_TURN_MAX_CHARS).
  public static let historyTurns = 6
  public static let turnMaxCharacters = 500

  public init() {}

  @discardableResult
  public mutating func append(_ role: ChatRole, _ text: String, at now: Date) -> ChatMessage {
    let message = ChatMessage(id: UUID(), role: role, text: text, at: now)
    append(message)
    return message
  }

  mutating func append(_ message: ChatMessage) {
    messages.append(message)
    if messages.count > Self.keep { messages.removeFirst(messages.count - Self.keep) }
  }

  /// The turns to send with a consultation at `now`: those of the last hour, the last six, each cut
  /// to 500 code points (the server counts code points, not what the screen shows as one character).
  /// A message with no time is never sent: how old it is cannot be known.
  public func history(at now: Date) -> [ConsultTurn] {
    turns(messages.filter { $0.at.map { now.timeIntervalSince($0) < Self.window } ?? false })
  }

  /// The turns to send with `text` at `now`. Words that only point back (`pointsBack`) get the
  /// conversation they point at, even from the day before: the hour is counted back from the last
  /// message instead of from now, so they get what a question right after it would have (#118,
  /// decided by the author on 2026-11-05). Nothing 30 days old or older goes. Other words get the
  /// last hour only. The server's own conversation of 60 minutes, which decides whether the family is
  /// told again, does not move with this.
  public func history(for text: String, at now: Date) -> [ConsultTurn] {
    guard Self.pointsBack(text), let last = messages.last?.at, last < now else {
      return history(at: now)
    }
    return turns(
      messages.filter { message in
        guard let at = message.at else { return false }
        return last.timeIntervalSince(at) < Self.window && now.timeIntervalSince(at) < Self.keptFor
      })
  }

  /// What the screen lists, oldest first, as in the usual chat apps (#113, decided by the author on
  /// 2026-11-05): a date row where the day changes in `calendar` ("11月4日", or "今日"), then each
  /// message with the time it was sent ("14:55"). A message with no time gets neither and starts no
  /// day. No year: nothing older than 30 days is kept.
  public func rows(at now: Date, calendar: Calendar = .current) -> [ChatRow] {
    var rows: [ChatRow] = []
    var shownDay: DateComponents?
    for message in messages {
      guard let at = message.at else {
        rows.append(.message(message, time: nil))
        continue
      }
      let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
      let day = DateComponents(year: parts.year, month: parts.month, day: parts.day)
      if day != shownDay {
        shownDay = day
        let label =
          calendar.isDate(at, inSameDayAs: now) ? "今日" : "\(parts.month ?? 0)月\(parts.day ?? 0)日"
        rows.append(.day(label: label, id: "day-\(message.id)"))
      }
      let hour = parts.hour ?? 0
      let minute = parts.minute ?? 0
      rows.append(
        .message(
          message,
          time: ChatStamp(
            text: String(format: "%02d:%02d", hour, minute), spoken: "\(hour)時\(minute)分")))
    }
    return rows
  }

  private func turns(_ kept: [ChatMessage]) -> [ConsultTurn] {
    kept
      .suffix(Self.historyTurns)
      .map { message in
        let cut = String(
          String.UnicodeScalarView(message.text.unicodeScalars.prefix(Self.turnMaxCharacters)))
        return ConsultTurn(role: message.role, text: cut)
      }
  }

  /// Words that only point back at what came just before ("それってどういうこと?", "どうすればいい?",
  /// "そのやり方を教えて"): short, beginning with a pointing or "how" word (after fillers, or as "なにそれ"),
  /// and no word that opens a new topic. A filler is one of a few roots stretched by ー, っ, a small vowel,
  /// or the vowel of its last kana ("ねえ", "えーっと", "あのう", "うーーん", #158). "振込のやり方を教えて" and "そうじのアプリを入れたい" start a new
  /// one; "その消し方を教えて" points back (#124).
  /// The same test as `pointsBack` in server/src/consult-judge.ts, which reads only such words as about
  /// her last earlier ones, so the app sends the conversation before for exactly the words the server
  /// reads that way. Both run server/test/fixtures/points-back.json; change them together.
  public static func pointsBack(_ text: String) -> Bool {
    // normalize() and /[\s\p{P}\p{S}]+/gu on the server: NFKC, lowercase, then no white space (as
    // JavaScript's \s), punctuation, or symbols.
    let lowered = text.precomposedStringWithCompatibilityMapping.lowercased()
    let kept = String(String.UnicodeScalarView(lowered.unicodeScalars.filter { !ignored($0) }))
    // The server counts code points.
    guard kept.unicodeScalars.count <= pointsBackMaxCharacters else { return false }
    // POINTS_BACK and NEW_TOPIC on the server, matched on code points as JavaScript's u flag does.
    let pointing =
      /^(ね[ーっぁぃぅぇぉえ]*|え[ーっぁぃぅぇぉえ]*(と[ーっぁぃぅぇぉお]*)?|あの[ーっぁぃぅぇぉおう]*|あ[ーっぁぃぅぇぉあ]*|う[ーっぁぃぅぇぉう]*ん[ーっ]*|は[ーっ]*い[ーっぁぃぅぇぉい]*|じゃ[ーっぁぃぅぇぉあ]*|で[ーっぁぃぅぇぉえ]*(も[ーっぁぃぅぇぉお]*)?|ちょ[ーっぁぃぅぇぉお]*と[ーっぁぃぅぇぉお]*)*((なに|何)?(それ|これ|あれ)|そう(なの|なん|か|です|でしょ|いう|$)|どうやる|どうやって|どうすれば|どうしたら|どういう|やり方|(この|その|あの)(やり方|方法|こと|件|やつ|操作|\p{Script=Han}\p{Script=Hiragana}?方))/
    let newTopic = /それより|それと|それから|ところで|別の|ほかの|他の/
    return kept.contains(pointing.matchingSemantics(.unicodeScalar))
      && !kept.contains(newTopic.matchingSemantics(.unicodeScalar))
  }

  /// POINTS_BACK_MAX_CHARS on the server.
  static let pointsBackMaxCharacters = 15

  /// JavaScript's \s (tab, line tabulation, form feed, the zero width no-break space, any space
  /// separator, and the line terminators), \p{P}, and \p{S}.
  private static func ignored(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0xFEFF, 0x2028, 0x2029: return true
    default: break
    }
    switch scalar.properties.generalCategory {
    case .spaceSeparator,
      .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
      .initialPunctuation, .finalPunctuation, .otherPunctuation,
      .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
      return true
    default:
      return false
    }
  }

  public func encoded() throws -> Data {
    try JSONEncoder().encode(self)
  }

  /// What a file held, without what is 30 days old or older. A missing or broken file starts an
  /// empty conversation.
  public static func restored(from data: Data?, at now: Date = .now) -> ChatLog {
    guard let data, var log = try? JSONDecoder().decode(ChatLog.self, from: data) else {
      return ChatLog()
    }
    // One with no time cannot be aged, so it goes too: her words do not stay on the iPhone for
    // months (docs/design.md, 30 days). The timed ones around it stay.
    log.messages.removeAll { $0.at.map { now.timeIntervalSince($0) >= keptFor } ?? true }
    if log.messages.count > keep { log.messages.removeFirst(log.messages.count - keep) }
    return log
  }
}

/// Where the conversation is kept. `read` throws while the file cannot be read (before the first
/// unlock, or while locked under NSFileProtectionComplete) and returns nil when there is none yet.
public protocol ChatLogStore: Sendable {
  func read() throws -> Data?
  func write(_ data: Data) throws
  /// Deletes the file. No file is not an error.
  func remove() throws
}

/// The conversation and its file. Nothing is written until the file has been read, so a launch
/// while the iPhone is locked cannot replace her history with an empty one.
public struct ChatKeeper: Sendable {
  private let store: any ChatLogStore
  public private(set) var log = ChatLog()
  public private(set) var isLoaded = false

  public init(store: any ChatLogStore) {
    self.store = store
  }

  /// Reads the file once it can be read. Messages added before that (kept in memory only) come
  /// after what the file held.
  public mutating func load(at now: Date = .now) {
    guard !isLoaded else { return }
    let data: Data?
    do {
      data = try store.read()
    } catch {
      return
    }
    let pending = log.messages
    log = ChatLog.restored(from: data, at: now)
    for message in pending { log.append(message) }
    isLoaded = true
  }

  /// Her words go out: returns the earlier turns to send with them (`ChatLog.history(for:at:)`), then
  /// keeps them.
  public mutating func send(_ text: String, at now: Date) -> [ConsultTurn] {
    load(at: now)
    let history = log.history(for: text, at: now)
    log.append(.protected, text, at: now)
    save()
    return history
  }

  public mutating func answered(_ reply: String, at now: Date) {
    load(at: now)
    log.append(.ai, reply, at: now)
    save()
  }

  /// This iPhone left the family (its key is gone): the conversation goes too, on the screen and in
  /// the file. What comes after is kept again.
  public mutating func clear() {
    log = ChatLog()
    try? store.remove()
    isLoaded = true
  }

  /// After data can be read again: when the app is back at role selection (the key went, say by a
  /// 401 while the iPhone was locked) and a conversation is still kept, it goes. Nothing happens
  /// while the file cannot be read.
  public mutating func forgetIfLeft(route: AppRoute, at now: Date = .now) {
    guard route == .chooseRole else { return }
    load(at: now)
    guard isLoaded, !log.messages.isEmpty else { return }
    clear()
  }

  private func save() {
    guard isLoaded, let data = try? log.encoded() else { return }
    try? store.write(data)
  }
}
