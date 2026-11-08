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
    case .notDeleted: "消せませんでした"
    case .notLeft: "外せませんでした"
    }
  }
}

/// The menu on both home screens (#279). The family's has "この iPhone を外す" and "家族を削除";
/// hers has her settings (`SettingsView`, #222) and "家族を削除" only (`HomeMenuItem` says why).
/// Each is checked before it runs with one verb or "やめる", nothing else on screen. What goes is
/// read aloud only. They were one "すべて消す" until the author, tidying only their own iPhone,
/// deleted the whole family with it.
struct WipeMenu: View {
  @Environment(AppModel.self) private var model
  @State private var confirmingLeave = false
  @State private var confirming = false
  @State private var settingsOpen = false

  var body: some View {
    Menu {
      // Which items, by role, is decided in Core (`HomeMenuItem`): her screen has no "この iPhone を外す".
      ForEach(HomeMenuItem.items(for: model.route), id: \.self) { item in
        switch item {
        case .settings:
          Button("設定", systemImage: "gearshape") { settingsOpen = true }
            .accessibilityHint("毎日の声かけ、その時刻、読み上げを切り替える画面を開きます")
        case .leaveDevice:
          Button("この iPhone を外す", systemImage: "iphone.slash", role: .destructive) {
            confirmingLeave = true
          }
          .accessibilityHint(
            "この iPhone だけを家族から外し、この iPhone の鍵を消して、役を選ぶ画面に戻ります。ほかの家族と見守られる人の登録はそのまま残ります")
        case .deleteFamily:
          Button("家族を削除", systemImage: "trash", role: .destructive) { confirming = true }
            .accessibilityHint(
              "家族の知らせ、相談、笑顔、Gmail の許可を裏側からすべて消し、家族全員を外して、役を選ぶ画面に戻ります。家族のみんなが使えなくなります")
        }
      }
    } label: {
      Image(systemName: model.isBusy ? "hourglass" : "ellipsis.circle")
        .font(.title2)
        .foregroundStyle(.secondary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .disabled(model.isBusy)
    .accessibilityLabel("その他")
    .alert("この iPhone を外す", isPresented: $confirmingLeave) {
      Button("外す", role: .destructive) { Task { await model.leaveFamily() } }
        .accessibilityHint("この iPhone だけが家族から外れます。ほかの家族はそのまま使えます")
      Button("やめる", role: .cancel) {}
    }
    // The name on the button says everyone goes, so it cannot be read as tidying this iPhone only.
    .alert("家族を削除", isPresented: $confirming) {
      Button("全員を削除", role: .destructive) { Task { await model.deleteEverything() } }
        .accessibilityHint("家族全員が外れ、知らせ、相談、笑顔、Gmail の許可が裏側から消えます")
      Button("やめる", role: .cancel) {}
    }
    .sheet(isPresented: $settingsOpen) { SettingsView() }
    .onAppear {
      #if DEBUG
        if ScreenshotStubTransport.settingsOpen, model.route == .protectedHome {
          settingsOpen = true
        }
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
