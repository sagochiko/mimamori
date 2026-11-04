import Foundation

// The protected person's screen is a chat (#73, decided by the author on 2026-11-04): what she said,
// by voice or in writing, on the right, and the AI's answers on the left, oldest first. The
// conversation stays on her iPhone only (the newest `keep`), and the turns of the same conversation
// go with her next consultation so "それってどういうこと?" can be answered. The server keeps none of it.
// The App's adapter reads and writes the file (NSFileProtectionComplete); everything else is here.

public enum ChatRole: String, Codable, Equatable, Sendable {
  case protected
  case ai
}

public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let role: ChatRole
  public let text: String
  public let at: Date

  public init(id: UUID, role: ChatRole, text: String, at: Date) {
    self.id = id
    self.role = role
    self.text = text
    self.at = at
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
  public func history(at now: Date) -> [ConsultTurn] {
    messages
      .filter { now.timeIntervalSince($0.at) < Self.window }
      .suffix(Self.historyTurns)
      .map { message in
        let cut = String(
          String.UnicodeScalarView(message.text.unicodeScalars.prefix(Self.turnMaxCharacters)))
        return ConsultTurn(role: message.role, text: cut)
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
    log.messages.removeAll { now.timeIntervalSince($0.at) >= keptFor }
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

  /// Her words go out: returns the earlier turns to send with them, then keeps them.
  public mutating func send(_ text: String, at now: Date) -> [ConsultTurn] {
    load(at: now)
    let history = log.history(at: now)
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

  private func save() {
    guard isLoaded, let data = try? log.encoded() else { return }
    try? store.write(data)
  }
}
