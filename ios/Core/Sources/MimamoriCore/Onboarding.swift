import Foundation

/// One button that gets a balloon the first time its screen opens. The author said on 2026-11-07
/// that after typing the code neither role could tell what the app does, and asked for balloons on
/// the real buttons, as the one exception to "no explanations on screen". The words stay about ten
/// characters, plain form, no 「、」; the longer explanation is VoiceOver's (`spoken`).
public enum OnboardingStep: String, CaseIterable, Sendable {
  case smile, talk, photo
  case invite, call, resolve

  /// The order on each home screen.
  public static func steps(for role: Role) -> [OnboardingStep] {
    switch role {
    case .protected: [.smile, .talk, .photo]
    case .family: [.invite, .call, .resolve]
    }
  }

  /// The words in the balloon.
  public var words: String {
    switch self {
    case .smile: "笑顔を家族に届ける"
    case .talk: "困ったら話しかけてね"
    case .photo: "画面の写真で聞ける"
    case .invite: "ほかの家族も呼べる"
    case .call: "すぐ母に電話できる"
    case .resolve: "話せたら解決を押す"
    }
  }

  /// What VoiceOver reads for the balloon.
  public var spoken: String {
    switch self {
    case .smile: "このボタンを押してカメラに笑いかけると、笑顔の写真が家族に届きます"
    case .talk: "困ったことは、下の欄に書くか、マイクを押して話しかけると、みまもりが答えます"
    case .photo: "このボタンでスクショを選ぶと、その画面のどこを押せばいいかを、みまもりが答えます"
    case .invite: "このボタンで招待のコードを出すと、ほかの家族もこの画面に入れます"
    case .call: "心配な知らせが来たら、このボタンで母にすぐ電話できます"
    case .resolve: "母と話して心配がなくなったら、解決を押すと、ほかの家族にも伝わります"
    }
  }
}

/// Which sample shows the balloons. Debug builds pick one with `-mimamori-onboarding tipkit` or
/// `-mimamori-onboarding spotlight`, until the author chooses.
public enum OnboardingStyle: String, Sendable {
  case tipKit = "tipkit"
  case spotlight

  public init?(arguments: [String]) {
    guard let i = arguments.firstIndex(of: "-mimamori-onboarding"), i + 1 < arguments.count,
      let style = OnboardingStyle(rawValue: arguments[i + 1])
    else { return nil }
    self = style
  }
}

/// The coach mark sample: the screen darkened, one button lit at a time, "次へ" and "1/3".
public struct CoachMarkTour: Equatable, Sendable {
  public let steps: [OnboardingStep]
  private var index = 0

  public init(role: Role) {
    steps = OnboardingStep.steps(for: role)
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
