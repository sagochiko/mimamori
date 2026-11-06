import Foundation

/// A size in pixels.
public struct PixelSize: Equatable, Sendable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// A point in pixels, from the top left.
public struct PixelPoint: Equatable, Sendable {
  public let x: Double
  public let y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// The size a shared image is sent at, and the way back from Claude's press point to the original.
///
/// Claude reads an image at the largest size that keeps its shape and fits both limits of its tier,
/// and gives points in that image (Claude docs, /docs/en/build-with-claude/vision-coordinates, "How
/// Claude resizes and pads images"). The app shrinks the image to exactly that size before sending it
/// ("Resize your image before uploading"), so the point comes back in the pixels of what was sent and
/// is scaled by the sent size, never by the size padded to 28. Sonnet 5.5 is on the high-resolution
/// tier: 2,576 px and 4,784 visual tokens (/docs/en/build-with-claude/vision, checked 2026-11-07).
/// The server refuses any other size (`fitsUnresized` in server/src/consult-judge.ts).
public enum CoordinateMapper {
  public static let maxEdge = 2576
  public static let maxTokens = 4784
  private static let patch = 28

  /// The size Claude reads an image of `size` at: the same when it fits, else the largest that does.
  /// A port of the docs' `resizedSize`, with its round-half-to-even.
  public static func sentSize(
    of size: PixelSize, maxEdge: Int = maxEdge, maxTokens: Int = maxTokens
  )
    -> PixelSize
  {
    func fits(_ w: Int, _ h: Int) -> Bool {
      let pw = (w + patch - 1) / patch
      let ph = (h + patch - 1) / patch
      return pw * patch <= maxEdge && ph * patch <= maxEdge && pw * ph <= maxTokens
    }
    let (w, h) = (size.width, size.height)
    guard w > 0, h > 0 else { return size }
    if fits(w, h) { return size }
    if h > w {
      let turned = sentSize(
        of: PixelSize(width: h, height: w), maxEdge: maxEdge, maxTokens: maxTokens)
      return PixelSize(width: turned.height, height: turned.width)
    }
    let aspect = Double(w) / Double(h)
    func other(_ long: Int) -> Int {
      max(Int((Double(long) / aspect).rounded(.toNearestOrEven)), 1)
    }
    var lo = 1
    var hi = w
    while lo + 1 < hi {
      let mid = (lo + hi) / 2
      if fits(mid, other(mid)) { lo = mid } else { hi = mid }
    }
    return PixelSize(width: lo, height: other(lo))
  }

  /// Claude's point on the sent image, on the original image. Nil when it is off the sent image.
  public static func original(x: Double, y: Double, sent: PixelSize, original: PixelSize)
    -> PixelPoint?
  {
    guard sent.width > 0, sent.height > 0 else { return nil }
    guard x >= 0, y >= 0, x < Double(sent.width), y < Double(sent.height) else { return nil }
    return PixelPoint(
      x: x * Double(original.width) / Double(sent.width),
      y: y * Double(original.height) / Double(sent.height))
  }
}
