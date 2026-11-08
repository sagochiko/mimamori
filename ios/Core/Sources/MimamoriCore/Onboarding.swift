import Foundation

/// One button that gets a balloon the first time its home screen opens (#283). The author said on
/// 2026-11-07 that after typing the code neither role could tell what the app does, and asked for
/// balloons on the real buttons, as the one exception to "no explanations on screen". On 2026-11-08
/// the author asked the words to say what each place is for rather than what can be done, and to end
/// every one the same way, 「〜してね」. The longer explanation is VoiceOver's (`spoken`).
public enum OnboardingStep: String, CaseIterable, Sendable {
  case smile, talk, photo
  case invite, familySmile, settings, call, resolve

  /// The order on each home screen. "電話する" and "解決" are on a card, so a family screen without a
  /// card skips them.
  public static func steps(for role: Role, hasCards: Bool) -> [OnboardingStep] {
    switch role {
    case .protected: [.smile, .talk, .photo]
    case .family: [.invite, .familySmile, .settings] + (hasCards ? [.call, .resolve] : [])
    }
  }

  /// The words in the balloon.
  public var words: String {
    switch self {
    case .smile: "ここで笑顔を撮って家族に届けてね"
    case .talk: "困ったことはここで話しかけてね"
    case .photo: "気になる画面の写真はここから送ってね"
    case .invite: "ここでコードを作ってほかの家族を呼んでね"
    case .familySmile: "ここで母の笑顔を見て笑顔を返してね"
    case .settings: "ここで笑顔の知らせと時刻を決めてね"
    case .call: "心配なときはここから母に電話してね"
    // Not tied to the call: the author said a family member may resolve without reaching her,
    // once it looks fine (2026-11-08).
    case .resolve: "問題なさそうならここで解決してね"
    }
  }

  /// What VoiceOver reads for the balloon.
  public var spoken: String {
    switch self {
    case .smile: "このボタンを押してカメラに笑いかけると、笑顔の写真が家族に届きます"
    case .talk: "困ったことは、下の欄に書くか、マイクを押して話しかけると、みまもりが答えます"
    case .photo: "このボタンで気になる画面のスクショを選んで送ると、どこを押せばいいかを、みまもりが答えます"
    case .invite: "このボタンで招待のコードを作ると、ほかの家族もこの画面に入れます"
    case .familySmile: "母の今日の笑顔はこの画面の上に出ます。このボタンで、家族からも笑顔を撮って返せます"
    case .settings: "このボタンのメニューで、笑顔が届いたときの知らせと、笑顔を待つ時刻を決められます"
    case .call: "心配な知らせが来たら、このボタンで母に電話できます"
    case .resolve: "問題なさそうだと分かったら、このボタンで解決にすると、ほかの家族にも伝わります"
    }
  }
}

/// The coach mark: the screen darkened, one button lit at a time, "次へ" and "1/3".
public struct CoachMarkTour: Equatable, Sendable {
  public let steps: [OnboardingStep]
  private var index = 0

  public init(steps: [OnboardingStep]) {
    self.steps = steps
  }

  /// Nil once the last "次へ" or the close button is pressed.
  public var current: OnboardingStep? { steps.indices.contains(index) ? steps[index] : nil }
  public var progress: String? { current == nil ? nil : "\(index + 1)/\(steps.count)" }
  public var isLast: Bool { index == steps.count - 1 }

  public mutating func next() {
    if index < steps.count { index += 1 }
  }

  public mutating func close() {
    index = steps.count
  }
}

/// Which roles' balloons this device has shown. UserDefaults in the App.
public protocol OnboardingStore: Sendable {
  func seen(_ role: Role) -> Bool
  func markSeen(_ role: Role)
  func clear()
}

public final class InMemoryOnboardingStore: OnboardingStore, @unchecked Sendable {
  private let lock = NSLock()
  private var roles: Set<String> = []
  public init() {}
  public func seen(_ role: Role) -> Bool { lock.withLock { roles.contains(role.rawValue) } }
  public func markSeen(_ role: Role) { _ = lock.withLock { roles.insert(role.rawValue) } }
  public func clear() { lock.withLock { roles = [] } }
}

/// Shows each role's balloons once per device. Marked seen when the tour starts, so a tour cut short
/// by closing the app does not come back.
public struct OnboardingRecord: Sendable {
  private let store: any OnboardingStore

  public init(store: any OnboardingStore) {
    self.store = store
  }

  /// The tour for a home screen opened for the first time, or nil. `force` (Debug screenshots) shows
  /// it regardless and leaves the record alone.
  public func tourIfFirst(role: Role, hasCards: Bool, force: Bool = false) -> CoachMarkTour? {
    if !force {
      guard !store.seen(role) else { return nil }
      store.markSeen(role)
    }
    return CoachMarkTour(steps: OnboardingStep.steps(for: role, hasCards: hasCards))
  }

  /// After "すべて消す": the next role on this iPhone starts fresh.
  public func forget() {
    store.clear()
  }
}
