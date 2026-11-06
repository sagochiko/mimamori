import Foundation
import Testing

@testable import MimamoriCore

/// The expected sizes come from the reference implementation in the Claude docs
/// (/docs/en/build-with-claude/vision-coordinates, "Resize your image before uploading"), run with
/// the high-resolution tier's limits (2,576 px, 4,784 visual tokens) on 2026-11-07.
@Suite("押す場所の座標")
struct CoordinateMapperTests {
  @Test("1179×2556 のスクショは縮めずにそのまま送る")
  func screenshotAsItIs() {
    #expect(
      CoordinateMapper.sentSize(of: PixelSize(width: 1179, height: 2556))
        == PixelSize(width: 1179, height: 2556))
  }

  @Test("長辺が2,576を超える画像は、Claude が読む寸法に縮める")
  func longEdgeOver() {
    #expect(
      CoordinateMapper.sentSize(of: PixelSize(width: 1290, height: 2796))
        == PixelSize(width: 1188, height: 2576))
    #expect(
      CoordinateMapper.sentSize(of: PixelSize(width: 1320, height: 2868))
        == PixelSize(width: 1186, height: 2576))
  }

  @Test("長辺が収まっても区切りの数が多すぎる画像は縮める")
  func tokenLimit() {
    #expect(
      CoordinateMapper.sentSize(of: PixelSize(width: 3000, height: 4000))
        == PixelSize(width: 1659, height: 2212))
  }

  @Test("公式の例の A4 は、標準の上限で924×1307になる")
  func docsExample() {
    #expect(
      CoordinateMapper.sentSize(
        of: PixelSize(width: 1075, height: 1520), maxEdge: 1568, maxTokens: 1568)
        == PixelSize(width: 924, height: 1307))
  }

  @Test("縮めていない画像では、返った座標をそのまま使う")
  func sameSize() {
    let size = PixelSize(width: 1179, height: 2556)
    #expect(
      CoordinateMapper.original(x: 540, y: 1210, sent: size, original: size)
        == PixelPoint(x: 540, y: 1210))
  }

  @Test("縮めた画像の座標は、縮めた寸法で割って元の画像に戻す(パディングした寸法は使わない)")
  func scaledBack() throws {
    let original = PixelSize(width: 1290, height: 2796)
    let sent = CoordinateMapper.sentSize(of: original)
    // Dividing by the padded size (1204×2576) would put the middle at x 636, short of 645.
    let origin = try #require(CoordinateMapper.original(x: 0, y: 0, sent: sent, original: original))
    #expect(origin == PixelPoint(x: 0, y: 0))
    let middle = try #require(
      CoordinateMapper.original(x: 594, y: 1288, sent: sent, original: original))
    #expect(middle == PixelPoint(x: 645, y: 1398))
  }

  @Test("画像の外の座標は捨てる")
  func outside() {
    let size = PixelSize(width: 1179, height: 2556)
    #expect(CoordinateMapper.original(x: 1179, y: 100, sent: size, original: size) == nil)
    #expect(CoordinateMapper.original(x: 100, y: 2557, sent: size, original: size) == nil)
    #expect(CoordinateMapper.original(x: -1, y: 100, sent: size, original: size) == nil)
  }
}
