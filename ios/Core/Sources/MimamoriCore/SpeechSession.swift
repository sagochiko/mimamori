/// Which lines handed to the speech synthesizer have not ended yet, so the app's audio session (which
/// lowers other apps' sound while it is active) is released right after the last one, and only then.
///
/// `ID` identifies one line (the app uses the utterance's `ObjectIdentifier`). Stopping forgets every
/// line at once; callbacks that arrive later for those lines are ignored, so they cannot end the
/// session of a line queued after the stop.
public struct SpeechSession<ID: Hashable & Sendable>: Sendable {
  private var pending: Set<ID> = []

  public init() {}

  public var isIdle: Bool { pending.isEmpty }

  public mutating func queued(_ ids: [ID]) {
    pending.formUnion(ids)
  }

  /// A line finished or was cancelled. True when it was the last one: release the session now.
  public mutating func ended(_ id: ID) -> Bool {
    pending.remove(id) != nil && pending.isEmpty
  }

  /// Everything was stopped. True when something was playing: release the session now.
  public mutating func stopped() -> Bool {
    defer { pending.removeAll() }
    return !pending.isEmpty
  }
}
