import Foundation
import MimamoriCore
import Testing
import UIKit

@testable import Mimamori

/// The image from the share sheet or the chat's photo button, shrunk and encoded the same way (#221).
@MainActor
struct ConsultPictureTests {
  private func image(width: Int, height: Int) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image
    {
      context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  @Test("iPhone のスクショの大きさなら縮めずに送り、JPEG の大きさも同じ")
  func screenshotSentAsIs() throws {
    let data = try #require(image(width: 1179, height: 2556).pngData())
    let picture = try #require(ConsultPicture(data: data))
    #expect(picture.original == PixelSize(width: 1179, height: 2556))
    #expect(picture.sent == picture.original)

    let sent = try #require(picture.encoded())
    #expect(sent.mediaType == .jpeg)
    #expect(sent.size == picture.sent)
    let decoded = try #require(UIImage(data: sent.data))
    #expect(decoded.size == CGSize(width: 1179, height: 2556))
    #expect(ConsultImage.fitsServer(byteCount: sent.data.count))
  }

  @Test("大きな画像は Claude が読む大きさに縮めて送り、丸は元の画像の上に戻す")
  func largeShrunk() throws {
    let data = try #require(image(width: 3000, height: 6000).pngData())
    let picture = try #require(ConsultPicture(data: data))
    #expect(picture.sent == CoordinateMapper.sentSize(of: PixelSize(width: 3000, height: 6000)))
    #expect(picture.sent.height < 6000)

    let sent = try #require(picture.encoded())
    let decoded = try #require(UIImage(data: sent.data))
    #expect(decoded.size == CGSize(width: sent.size.width, height: sent.size.height))

    let answer = ConsultAnswer(
      reply: "ここ", speak: "ここ",
      tap: .init(x: Double(picture.sent.width) / 2, y: Double(picture.sent.height) / 2),
      handoff: false)
    let circle = try #require(picture.circle(for: answer))
    #expect(abs(circle.x - 1500) < 1)
    #expect(abs(circle.y - 3000) < 1)
  }

  @Test("画像でないものは読めない")
  func notAnImage() {
    #expect(ConsultPicture(data: Data("これはテキスト".utf8)) == nil)
  }

  /// A made-up Settings-like screen: rows of text and coloured icons on the system background, the
  /// kind of screenshot she shows. Plain colour compresses to almost nothing and says nothing of size.
  private func settingsScreen(width: Int = 1179, height: Int = 2556) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image {
      context in
      UIColor.systemGroupedBackground.setFill()
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      let font = UIFont.systemFont(ofSize: 50)
      let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPink, .systemPurple]
      for row in 0..<30 {
        let y = CGFloat(140 + row * 80)
        colors[row % colors.count].setFill()
        context.fill(CGRect(x: 60, y: y + 10, width: 58, height: 58))
        let text = "写真とビデオ メッセージ \(row * 37 % 100).\(row % 10) GB 設定 一般 ストレージ"
        (text as NSString).draw(
          at: CGPoint(x: 150, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.label])
      }
    }
  }

  @Test("会話に残す画像は長い辺1024ピクセルの JPEG で、300KB を超えず、送る画像より小さい(#243)")
  func keptSmaller() throws {
    let png = try #require(settingsScreen().pngData())
    let picture = try #require(ConsultPicture(data: png))
    let kept = try #require(picture.kept())
    let decoded = try #require(UIImage(data: kept))
    #expect(decoded.size == CGSize(width: 472, height: 1024))
    #expect(kept.count <= ChatPicture.maxBytes)
    let sent = try #require(picture.encoded())
    #expect(kept.count < sent.data.count)
    // Measured on the simulator (docs/design.md, #243): printed for the record.
    print("kept picture: \(kept.count) bytes, sent: \(sent.data.count) bytes")
  }
}
