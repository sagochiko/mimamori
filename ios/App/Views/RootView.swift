import MimamoriCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var guide = OnboardingGuide()

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
    // The balloons over the buttons of the home screen, once per role (the overlay covers the toolbar too).
    .environment(guide)
    .overlay { if guide.tour != nil { CoachMarkOverlay().environment(guide) } }
    .task(id: GuideKey(route: model.route, joined: model.protectedJoined)) {
      // The cards first, so a family screen with a card lights "電話する" and "解決" too.
      if model.route == .familyHome, model.protectedJoined { await model.loadCases() }
      guide.start(
        for: model.route, joined: model.protectedJoined,
        hasCards: model.familyCards.contains { !$0.actions.isEmpty })
    }
    .alert(
      model.problem.map(\.title) ?? "",
      isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })
    ) {
      Button("OK", role: .cancel) {}
    }
  }
}

private struct GuideKey: Equatable {
  let route: AppRoute
  let joined: Bool
}

extension Problem {
  var title: String {
    switch self {
    case .badCode: "コードが違います"
    case .unreachable: "つながりません"
    case .notDeleted: "消せませんでした"
    }
  }
}

/// The menu on both home screens with "すべて消す", and the check before it: "消す" or "やめる",
/// nothing else on screen. What goes is read aloud only. On her screen it also opens her settings
/// (`SettingsView`, #222); the family's iPhone has no daily prompt or reading aloud.
struct WipeMenu: View {
  @Environment(AppModel.self) private var model
  @State private var confirming = false
  @State private var settingsOpen = false

  var body: some View {
    Menu {
      if model.route == .protectedHome {
        Button("設定", systemImage: "gearshape") { settingsOpen = true }
          .accessibilityHint("毎日の声かけ、その時刻、読み上げを切り替える画面を開きます")
      }
      Button("すべて消す", systemImage: "trash", role: .destructive) { confirming = true }
        .accessibilityHint("家族の知らせ、相談、笑顔、Gmail の許可を裏側からすべて消し、この iPhone の鍵と会話も消して、役を選ぶ画面に戻ります。家族のみんなが使えなくなります")
    } label: {
      Image(systemName: model.isBusy ? "hourglass" : "ellipsis.circle")
        .font(.title2)
        .foregroundStyle(.secondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .disabled(model.isBusy)
    .accessibilityLabel("その他")
    .alert("すべて消す", isPresented: $confirming) {
      Button("消す", role: .destructive) { Task { await model.deleteEverything() } }
      Button("やめる", role: .cancel) {}
    }
    .sheet(isPresented: $settingsOpen) { SettingsView() }
    .onAppear {
      #if DEBUG
        if ScreenshotStubTransport.settingsOpen, model.route == .protectedHome { settingsOpen = true }
        if ScreenshotStubTransport.wipeOpen { confirming = true }
      #endif
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
