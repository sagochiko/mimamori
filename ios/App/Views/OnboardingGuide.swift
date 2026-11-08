import MimamoriCore
import SwiftUI

/// Balloons on the real buttons that say what each one is for, the first time a home screen opens on
/// this iPhone (#283). The author chose the coach mark on 2026-11-08: the screen darkens, one button at
/// a time is lit with "1/3" and "次へ". Each role's tour shows once (`OnboardingRecord`); Debug builds
/// show it again with `-mimamori-onboarding`, for screenshots.
@MainActor @Observable
final class OnboardingGuide {
  /// Which button is lit, and where each target sits on the screen.
  var tour: CoachMarkTour?
  var frames: [OnboardingStep: CGRect] = [:]
  @ObservationIgnored private let record = OnboardingRecord(store: UserDefaultsOnboardingStore())

  /// Debug only: show the tour on every launch and leave the record alone.
  private static var forced: Bool {
    #if DEBUG
      ProcessInfo.processInfo.arguments.contains("-mimamori-onboarding")
    #else
      false
    #endif
  }

  /// The stub's screenshot runs would all be covered by the tour, so it shows there only when asked.
  private static var suppressed: Bool {
    #if DEBUG
      ScreenshotStubTransport.isRequested && !forced
    #else
      false
    #endif
  }

  /// Called when the route changes and once the home screen is ready. A tour already going on stays.
  /// The family's toolbar buttons appear only after the protected member joined, so the family's tour
  /// waits for that; "電話する" and "解決" are lit only when an unresolved card is on screen.
  func start(for route: AppRoute, joined: Bool, hasCards: Bool) {
    switch route {
    case .chooseRole:
      // After "すべて消す" (or a lost key) this iPhone starts over, so the next role sees its tour.
      tour = nil
      frames = [:]
      if !Self.forced { record.forget() }
    case .protectedHome:
      begin(role: .protected, hasCards: false)
    case .familyHome:
      if joined { begin(role: .family, hasCards: hasCards) }
    }
  }

  private func begin(role: Role, hasCards: Bool) {
    guard tour == nil, !Self.suppressed else { return }
    tour = record.tourIfFirst(role: role, hasCards: hasCards, force: Self.forced)
  }
}

struct UserDefaultsOnboardingStore: OnboardingStore {
  private func key(_ role: Role) -> String { "mimamori.onboardingSeen.\(role.rawValue)" }
  func seen(_ role: Role) -> Bool { UserDefaults.standard.bool(forKey: key(role)) }
  func markSeen(_ role: Role) { UserDefaults.standard.set(true, forKey: key(role)) }
  func clear() {
    for role in Role.allCases { UserDefaults.standard.removeObject(forKey: key(role)) }
  }
}

extension View {
  /// Marks the button a balloon points at. Nil changes nothing.
  func guideTarget(_ step: OnboardingStep?) -> some View {
    modifier(GuideTarget(step: step))
  }
}

private struct GuideTarget: ViewModifier {
  let step: OnboardingStep?
  @Environment(OnboardingGuide.self) private var guide: OnboardingGuide?

  func body(content: Content) -> some View {
    if let step, let guide {
      content.onGeometryChange(
        for: CGRect.self, of: { $0.frame(in: .global) }, action: { guide.frames[step] = $0 })
    } else {
      content
    }
  }
}

/// The coach mark over the whole screen: dark everywhere but the lit button, and a balloon with the
/// words, "1/3", and "次へ" (on the last, "閉じる"). Taps on the dark part do nothing. VoiceOver reads
/// only the balloon, and moves to it on each step.
struct CoachMarkOverlay: View {
  @Environment(OnboardingGuide.self) private var guide
  @AccessibilityFocusState private var balloonFocused: Bool

  /// White in light mode; in dark mode a gray lighter than the black screen under the dimming.
  private static let balloonFill = Color(.tertiarySystemBackground)

  var body: some View {
    GeometryReader { proxy in
      let origin = proxy.frame(in: .global).origin
      if let step = guide.tour?.current, let frame = guide.frames[step] {
        let hole = frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6)
        let below = hole.midY < proxy.size.height / 2
        ZStack {
          Path { path in
            path.addRect(CGRect(origin: .zero, size: proxy.size))
            // Round like the buttons and the field it lights.
            let radius = min(hole.width, hole.height) / 2
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius))
          }
          .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
          .contentShape(Rectangle())
          .onTapGesture {}
          .accessibilityHidden(true)
          // The balloon's point, toward the lit button.
          Path { path in
            let x = min(max(hole.midX, 32), proxy.size.width - 32)
            let base = below ? hole.maxY + 14 : hole.minY - 14
            let tip = below ? hole.maxY + 4 : hole.minY - 4
            path.move(to: CGPoint(x: x - 10, y: base))
            path.addLine(to: CGPoint(x: x, y: tip))
            path.addLine(to: CGPoint(x: x + 10, y: base))
            path.closeSubpath()
          }
          .fill(Self.balloonFill)
          .accessibilityHidden(true)
          balloon(step: step)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
            .padding(.top, below ? hole.maxY + 13 : 0)
            .padding(.bottom, below ? 0 : proxy.size.height - hole.minY + 13)
        }
        .animation(.snappy, value: step)
        .onChange(of: step, initial: true) { balloonFocused = true }
      }
    }
    .ignoresSafeArea()
  }

  private func balloon(step: OnboardingStep) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(step.words)
        .font(.title3.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("\(spokenProgress)。\(step.words)。\(step.spoken)")
        .accessibilityFocused($balloonFocused)
      HStack {
        Text(guide.tour?.progress ?? "")
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Spacer()
        Button(guide.tour?.isLast == true ? "閉じる" : "次へ") {
          guide.tour?.next()
        }
        .font(.headline)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .accessibilityHint(guide.tour?.isLast == true ? "説明を閉じて使い始めます" : "次のボタンの説明に進みます")
      }
    }
    .padding(16)
    .frame(maxWidth: 360, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 18).fill(Self.balloonFill))
    // In dark mode the dimmed screen is near black too; a faint edge keeps the balloon apart.
    .overlay(
      RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
  }

  private var spokenProgress: String {
    guard let tour = guide.tour, let current = tour.current,
      let i = tour.steps.firstIndex(of: current)
    else { return "" }
    return "\(tour.steps.count)つのうち\(i + 1)つ目"
  }
}
