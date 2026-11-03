import MimamoriCore
import SwiftUI

/// Entering the 6-digit invite code. Only ASCII digits are kept while typing.
struct JoinView: View {
  @Environment(AppModel.self) private var model
  let role: Role
  var displayName: String = "見守られる人"

  @State private var typed = ""
  @FocusState private var focused: Bool

  private var code: InviteCode? { InviteCode(typed) }

  var body: some View {
    VStack(spacing: 32) {
      Spacer()
      TextField("000000", text: $typed)
        .font(.system(size: 56, weight: .semibold, design: .monospaced))
        .multilineTextAlignment(.center)
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .focused($focused)
        .onChange(of: typed) { _, new in
          let clean = InviteCode.sanitize(new)
          if clean != new { typed = clean }
        }
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
        .accessibilityLabel("招待のコード")
        .accessibilityHint("家族のスマホに出ている6桁の数字を入れます")

      Button {
        guard let code else { return }
        Task { await model.join(code: code, role: role, displayName: displayName) }
      } label: {
        if model.isBusy { ProgressView().tint(.white) } else { Text("入る") }
      }
      .buttonStyle(BigButtonStyle())
      .disabled(code == nil || model.isBusy)
      .accessibilityHint(code == nil ? "6桁の数字を入れると押せます" : "このコードの家族に入ります")
      Spacer()
      Spacer()
    }
    .padding(24)
    .onAppear { focused = true }
  }
}
