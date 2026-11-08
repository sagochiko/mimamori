import MimamoriCore
import SwiftUI

/// A family member either creates the family (the first one) or joins with a code.
struct FamilyStartView: View {
  @Environment(AppModel.self) private var model
  @State private var name = ""

  private var trimmed: String { DisplayName.trimmed(name) }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      // "あなたの名前", not "名前": the author could not tell whether it asked for the family's name or
      // their own (#279). It is members.display_name, shown on the other members' screens.
      TextField("あなたの名前", text: $name)
        .font(.title2)
        .textContentType(.givenName)
        .submitLabel(.done)
        // The server refuses names over 40 (UTF-16), so they never get that far.
        .onChange(of: name) { _, new in
          let limited = DisplayName.limit(new)
          if limited != new { name = limited }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .accessibilityLabel("あなたの名前")
        .accessibilityHint("家族の画面に出る名前です。家族の名前ではなく、あなた自身の名前を入れます。40文字までです。相談を解決にしたときにこの名前が出ます")

      Button {
        Task { await model.createFamily(displayName: trimmed) }
      } label: {
        if model.isBusy { ProgressView().tint(.white) } else { Text("作る") }
      }
      .buttonStyle(BigButtonStyle())
      .disabled(!DisplayName.isValid(name) || model.isBusy)
      .accessibilityLabel("家族を作る")
      .accessibilityHint("最初の1人が選びます。作ったあと、ほかの人に渡す招待のコードを出せます")

      NavigationLink {
        JoinView(role: .family, displayName: trimmed)
      } label: {
        Text("入る")
      }
      .buttonStyle(BigButtonStyle(prominent: false))
      .disabled(!DisplayName.isValid(name))
      .accessibilityLabel("コードで入る")
      .accessibilityHint("ほかの家族が出した6桁のコードで、同じ家族に入ります")
      Spacer()
    }
    .padding(24)
  }
}
