import MimamoriCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    NavigationStack {
      switch model.route {
      case .chooseRole: RoleSelectionView()
      case .protectedHome: ProtectedHomeView()
      case .familyHome: FamilyHomeView()
      }
    }
    // A new stack per route: after joining (or a 401) the pushed code or name screen must not stay on top.
    .id(model.route)
    .animation(.default, value: model.route)
    .alert(
      model.problem.map(\.title) ?? "",
      isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })
    ) {
      Button("OK", role: .cancel) {}
    }
  }
}

extension Problem {
  var title: String {
    switch self {
    case .badCode: "コードが違います"
    case .unreachable: "つながりません"
    }
  }
}

/// A full-width button with large text, used for every main action. Greyed out while disabled.
struct BigButtonStyle: ButtonStyle {
  var prominent = true

  func makeBody(configuration: Configuration) -> some View {
    BigButtonBody(configuration: configuration, prominent: prominent)
  }
}

private struct BigButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let prominent: Bool
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let tint = isEnabled ? Color.accentColor : Color.secondary
    configuration.label
      .font(.title.bold())
      .frame(maxWidth: .infinity, minHeight: 88)
      .foregroundStyle(prominent ? Color.white : tint)
      .background(
        RoundedRectangle(cornerRadius: 20)
          .fill(prominent ? tint : tint.opacity(0.18))
      )
      // The secondary button also gets an outline: in dark mode a faint fill alone is nearly black.
      .overlay {
        if !prominent {
          RoundedRectangle(cornerRadius: 20).strokeBorder(tint, lineWidth: 2)
        }
      }
      .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.5)
  }
}
