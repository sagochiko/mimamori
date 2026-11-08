import MimamoriCore
import SwiftUI
import UIKit

/// The taps in iPhone Settings that turn on the Safari extension or the SMS filter (#287), one
/// screenshot per tap with a red ring and its number, and a button at the bottom that opens Settings.
/// These lines are steps she reads and follows, so each keeps its one line under the picture.
struct ExtensionGuideView: View {
  let guide: ExtensionGuide
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
          VStack(alignment: .leading, spacing: 8) {
            if let image = step.image {
              Image(image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                .accessibilityLabel(guide.spokenLabel(at: index))
            }
            Text("\(index + 1). \(step.caption)")
              .font(.body)
              .accessibilityHidden(step.image != nil)
          }
        }
        Button {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } label: {
          Text("設定を開く").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("iPhone の設定を開きます。上の順に押してください")
      }
      .padding()
    }
    .navigationTitle(guide.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
