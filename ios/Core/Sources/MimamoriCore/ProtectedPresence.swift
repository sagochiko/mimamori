import Foundation

// Whether the protected member has joined, as a family member's iPhone can tell (#244,
// docs/design.md, "家族の画面"). Before she joins, the family screen shows only "招待"; after, her
// smile and the cards. There is no member list in the API (docs/plan.md), so it is read from what
// the screen already loads: a smile sent by the protected role, or any case (a case only comes from
// her iPhone). Once seen it is kept on this device, so a quiet week, when her smiles leave the 7-day
// window of `GET /smiles`, does not bring back the invite-only screen.

public protocol ProtectedPresenceStore: Sendable {
  func load() -> Bool
  func save(_ joined: Bool)
}

public final class InMemoryProtectedPresenceStore: ProtectedPresenceStore, @unchecked Sendable {
  private let lock = NSLock()
  private var joined = false
  public init() {}
  public func load() -> Bool { lock.withLock { joined } }
  public func save(_ joined: Bool) { lock.withLock { self.joined = joined } }
}

public final class ProtectedPresence: @unchecked Sendable {
  private let store: any ProtectedPresenceStore
  private let lock = NSLock()
  private var joined: Bool

  public init(store: any ProtectedPresenceStore) {
    self.store = store
    self.joined = store.load()
  }

  public var hasJoined: Bool { lock.withLock { joined } }

  /// Looks at the latest smiles and cases, and returns whether she has joined. A smile of someone who
  /// left (no role) does not count.
  @discardableResult
  public func update(smiles: [Smile], cases: [Case]) -> Bool {
    lock.withLock {
      if !joined, !cases.isEmpty || smiles.contains(where: { $0.role == .protected }) {
        joined = true
        store.save(true)
      }
      return joined
    }
  }

  /// This iPhone left the family, or everything was deleted.
  public func forget() {
    lock.withLock {
      joined = false
      store.save(false)
    }
  }
}
