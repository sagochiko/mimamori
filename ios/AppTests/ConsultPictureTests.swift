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
}
