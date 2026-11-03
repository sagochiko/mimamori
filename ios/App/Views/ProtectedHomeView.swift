import SwiftUI

/// The protected person's screen: one big microphone. Smiles and alerts join it in later tasks;
/// the microphone starts working in task 12.
struct ProtectedHomeView: View {
  var body: some View {
    VStack {
      Spacer()
      Image(systemName: "mic.fill")
        .font(.system(size: 96, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 220, height: 220)
        .background(Circle().fill(Color.accentColor))
        .accessibilityElement()
        .accessibilityLabel("話しかけるボタン")
        .accessibilityHint("準備中です。もうすぐ、押して話すとスマホの困りごとに答えます")
      Spacer()
    }
    .padding(24)
  }
}
