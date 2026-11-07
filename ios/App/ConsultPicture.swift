import MimamoriCore
import SwiftUI
import UIKit

/// A screenshot or a photo of a document on its way to POST /consult, from the share sheet
/// (ios/ShareExtension) or from the photo button in her chat (#221). Shared by both targets
/// (ios/project.yml), so the image is shrunk, sent, and circled the same way from either.
///
/// What is sent is only held in memory and never kept on the server (docs/design.md, "スクショはその場で
/// 処理して残さない"). From the chat, a smaller copy (`kept()`) stays with her conversation on the iPhone
/// (#243); the share sheet keeps nothing. Its words are data for Claude, never for this code.
struct ConsultPicture {
  /// The image as she picked it, with its orientation applied, at one pixel per point.
  let image: UIImage
  let original: PixelSize
  /// The size Claude reads it at (`CoordinateMapper.sentSize`); the answer's `tap` is in these pixels.
  let sent: PixelSize

  init?(_ image: UIImage) {
    let original = PixelSize(
      width: Int(image.size.width.rounded()), height: Int(image.size.height.rounded()))
    guard original.width > 0, original.height > 0 else { return nil }
    self.image = image
    self.original = original
    self.sent = CoordinateMapper.sentSize(of: original)
  }

  /// From the bytes of a picked or shared image (JPEG, PNG, HEIC). `UIImage(data:)` reads at scale 1.
  init?(data: Data) {
    guard let image = UIImage(data: data) else { return nil }
    self.init(image)
  }

  /// The image drawn at exactly `sent` pixels, as JPEG. A lower quality is tried when the first one
  /// is over what the server takes (`ConsultImage.fitsServer`).
  func encoded() -> ConsultImage? {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let target = CGSize(width: sent.width, height: sent.height)
    let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    for quality in ConsultImage.jpegQualities {
      guard let data = drawn.jpegData(compressionQuality: quality) else { continue }
      if ConsultImage.fitsServer(byteCount: data.count) {
        return ConsultImage(mediaType: .jpeg, data: data, size: sent)
      }
    }
    return nil
  }

  /// The copy kept with her conversation (#243): at most `ChatPicture.maxEdge` pixels on its longest
  /// edge, as JPEG at the first of `ChatPicture.jpegQualities` within `ChatPicture.maxBytes`. Nil when
  /// none is, and then nothing is kept.
  func kept() -> Data? {
    let size = ChatPicture.keptSize(of: original)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let target = CGSize(width: size.width, height: size.height)
    let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    for quality in ChatPicture.jpegQualities {
      guard let data = drawn.jpegData(compressionQuality: quality) else { continue }
      if data.count <= ChatPicture.maxBytes { return data }
    }
    return nil
  }

  /// Where the ring goes on the image, from the answer's `tap`.
  func circle(for answer: ConsultAnswer) -> PixelPoint? {
    ShareConsult.circle(for: answer, sent: sent, original: original)
  }
}

/// The image she showed, fitted, with a ring where to press.
struct CircledImage: View {
  let image: UIImage
  let original: PixelSize
  let circle: PixelPoint?

  var body: some View {
    GeometryReader { geo in
      let scale = min(
        geo.size.width / CGFloat(original.width), geo.size.height / CGFloat(original.height))
      let shown = CGSize(
        width: CGFloat(original.width) * scale, height: CGFloat(original.height) * scale)
      let origin = CGPoint(
        x: (geo.size.width - shown.width) / 2, y: (geo.size.height - shown.height) / 2)
      ZStack(alignment: .topLeading) {
        Image(uiImage: image)
          .resizable()
          .frame(width: shown.width, height: shown.height)
          .offset(x: origin.x, y: origin.y)
        if let circle {
          Circle()
            .stroke(Color.red, lineWidth: 5)
            .frame(width: 56, height: 56)
            .position(x: origin.x + circle.x * scale, y: origin.y + circle.y * scale)
        }
      }
    }
    .accessibilityElement()
    .accessibilityLabel(circle == nil ? "見せた画像" : "見せた画像。押す場所に赤い丸")
  }
}
