import MimamoriCore
import SwiftUI

/// The first screen: who is this phone for. No heading; the two names say it.
struct RoleSelectionView: View {
  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      NavigationLink {
        JoinView(role: .protected)
      } label: {
        Label("見守られる人", systemImage: "heart.fill")
      }
      .buttonStyle(BigButtonStyle())
      .accessibilityLabel("見守られる人")
      .accessibilityHint("見守ってもらう人のスマホで選びます。家族から聞いた6桁のコードを入れます")

      NavigationLink {
        FamilyStartView()
      } label: {
        Label("家族", systemImage: "person.2.fill")
      }
      .buttonStyle(BigButtonStyle(prominent: false))
      .accessibilityLabel("家族")
      .accessibilityHint("見守る家族のスマホで選びます。家族を作るか、6桁のコードで入ります")

      // The judges' build only (#100). The mother's build carries her family's token, so she never sees
      // it; until #133 is done she gets the `demo` build and sees it here too (it sends nothing).
      if AppConfig.isDemo {
        NavigationLink {
          DemoView()
        } label: {
          Label("体験", systemImage: "play.circle")
        }
        .buttonStyle(BigButtonStyle(prominent: false))
        .accessibilityLabel("体験")
        .accessibilityHint("家族に入らずに、母の画面と家族に届くカードをこのiPhoneで見られます。誰にも知らせません")
      }
      Spacer()
    }
    .padding(24)
  }
}
