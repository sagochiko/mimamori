import MimamoriCore
import SwiftUI
import TipKit

/// Balloons on the real buttons that say what each one does, the first time a home screen opens
/// (asked by the author on 2026-11-07). Two samples to compare, sharing `OnboardingStep`'s words and
/// order: TipKit's popover tips, one at a time with ×, and a coach mark of our own that darkens the
/// screen and lights one button at a time with "1/3" and "次へ". Until the author picks one, only
/// Debug builds show them, with `-mimamori-onboarding tipkit` or `-mimamori-onboarding spotlight`.
@MainActor @Observable
final class OnboardingGuide {
  static let style: OnboardingStyle? = {
    #if DEBUG
      OnboardingStyle(arguments: ProcessInfo.processInfo.arguments)
    #else
      nil
    #endif
  }()

  /// Before any tip shows (`Tips.configure` must run at launch). The samples forget what was closed,
  /// so each launch shows them again.
  static func configure() {
    guard style == .tipKit else { return }
    #if DEBUG
      try? Tips.resetDatastore()
    #endif
    try? Tips.configure([.displayFrequency(.immediate)])
  }

  /// TipKit: the tips of the open home screen, shown in order; the next comes after × on the last.
  private(set) var tips: TipGroup?
  /// The coach mark: which button is lit, and where each target sits on the screen.
  var tour: CoachMarkTour?
  var frames: [OnboardingStep: CGRect] = [:]

  func start(for route: AppRoute) {
    let role: Role? =
      switch route {
      case .protectedHome: .protected
      case .familyHome: .family
      case .chooseRole: nil
      }
    frames = [:]
    tips = nil
    tour = nil
    guard let role, let style = Self.style else { return }
    switch style {
    case .tipKit: tips = Self.group(for: role)
    case .spotlight: tour = CoachMarkTour(role: role)
    }
  }

  func tip(for step: OnboardingStep) -> GuideTip? {
    guard let tip = tips?.currentTip as? GuideTip, tip.step == step else { return nil }
    return tip
  }

  private static func group(for role: Role) -> TipGroup {
    switch role {
    case .protected:
      TipGroup(.ordered) {
        GuideTip(step: .smile)
        GuideTip(step: .talk)
        GuideTip(step: .photo)
      }
    case .family:
      TipGroup(.ordered) {
        GuideTip(step: .invite)
        GuideTip(step: .call)
        GuideTip(step: .resolve)
      }
    }
  }
}

/// One balloon of the TipKit sample: the short words only, the explanation read by VoiceOver.
struct GuideTip: Tip {
  let step: OnboardingStep
  var id: String { step.rawValue }
  var title: Text { Text(step.words).accessibilityLabel(step.spoken) }
}

extension View {
  /// Marks the button a balloon points at. Nil, or with no sample chosen, changes nothing.
  func guideTarget(_ step: OnboardingStep?) -> some View {
    modifier(GuideTarget(step: step))
  }
}

private struct GuideTarget: ViewModifier {
  let step: OnboardingStep?
  @Environment(OnboardingGuide.self) private var guide: OnboardingGuide?

  func body(content: Content) -> some View {
    if let step, let guide {
      switch OnboardingGuide.style {
      case .tipKit:
        // Above the field at the bottom, so the balloon does not cover the field.
        content.popoverTip(guide.tip(for: step), arrowEdge: step == .photo || step == .talk ? .bottom : nil)
      case .spotlight:
        content.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) {
          guide.frames[step] = $0
        }
      case nil:
        content
      }
    } else {
      content
    }
  }
}

/// The coach mark sample over the whole screen: dark everywhere but the lit button, and a balloon
/// with the words, "1/3", and "次へ" (on the last, "閉じる"). Taps on the dark part do nothing.
struct CoachMarkOverlay: View {
  @Environment(OnboardingGuide.self) private var guide

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
          .fill(Color(.systemBackground))
          .accessibilityHidden(true)
          balloon(step: step)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: below ? .top : .bottom)
            .padding(.top, below ? hole.maxY + 13 : 0)
            .padding(.bottom, below ? 0 : proxy.size.height - hole.minY + 13)
        }
        .animation(.snappy, value: step)
      }
    }
    .ignoresSafeArea()
  }

  private func balloon(step: OnboardingStep) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(step.words)
        .font(.title3.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(step.spoken)
      HStack {
        Text(guide.tour?.progress ?? "")
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .accessibilityLabel(spokenProgress)
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
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.systemBackground)))
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
