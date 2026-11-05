#if DEBUG
  import MimamoriCore
  import SwiftUI
  import UIKit

  /// Debug builds only: a smiling face drawn in code, standing in for the camera's photo on the
  /// simulator (which has no camera or face tracking). No photo of a person is in the repository.
  enum SmilePlaceholder {
    private static let backgrounds: [UIColor] = [.systemOrange, .systemTeal, .systemPink, .systemGreen, .systemIndigo]

    /// A 480-pixel square JPEG. `variant` picks the background, so tiles differ.
    static func jpeg(variant: Int = 0) -> Data {
      let size = CGSize(width: 480, height: 480)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        let cg = context.cgContext
        backgrounds[abs(variant) % backgrounds.count].withAlphaComponent(0.35).setFill()
        cg.fill(CGRect(origin: .zero, size: size))
        UIColor(red: 1, green: 0.86, blue: 0.7, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: 90, y: 80, width: 300, height: 330))
        UIColor.darkGray.setFill()
        for x in [175.0, 285.0] {
          cg.fillEllipse(in: CGRect(x: x - 16, y: 195, width: 32, height: 22))
        }
        UIColor.systemPink.withAlphaComponent(0.35).setFill()
        for x in [150.0, 330.0] {
          cg.fillEllipse(in: CGRect(x: x - 30, y: 255, width: 60, height: 34))
        }
        let mouth = UIBezierPath()
        mouth.move(to: CGPoint(x: 170, y: 290))
        mouth.addQuadCurve(to: CGPoint(x: 310, y: 290), controlPoint: CGPoint(x: 240, y: 370))
        mouth.lineWidth = 14
        mouth.lineCapStyle = .round
        UIColor.darkGray.setStroke()
        mouth.stroke()
      }
      return image.jpegData(compressionQuality: 0.7) ?? Data()
    }
  }

  /// Stands in for `SmileCameraPreview` on the simulator: shows the drawn face as the "camera" and
  /// "sees" a smile after a moment, unless launched with `-mimamori-stub-camera-hold`.
  struct StubSmileCamera: View {
    let onSmile: (Data, Double) -> Void
    private let jpeg = SmilePlaceholder.jpeg(variant: 0)

    var body: some View {
      // The square picture fills the screen inside a frame of the screen's size. Filled on its own, it
      // was wider than the screen and pushed "やめる" off its left edge.
      Color.clear
        .overlay {
          if let image = UIImage(data: jpeg) {
            Image(uiImage: image).resizable().scaledToFill()
          }
        }
        .clipped()
        .ignoresSafeArea()
      .accessibilityLabel("前のカメラ")
      .task {
        guard !ScreenshotStubTransport.cameraHold else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        onSmile(jpeg, 0.82)
      }
    }
  }
#endif
