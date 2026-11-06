import Foundation

/// A screenshot or a photo of a document she shares to the app (ios/ShareExtension), as POST /consult
/// takes it: already at the size Claude reads it at (`CoordinateMapper.sentSize`). It goes to the
/// server and is kept nowhere on the way.
public struct ConsultImage: Sendable, Equatable {
  public enum MediaType: String, Sendable {
    case jpeg = "image/jpeg"
    case png = "image/png"
  }

  public let mediaType: MediaType
  public let data: Data
  public let size: PixelSize

  public init(mediaType: MediaType, data: Data, size: PixelSize) {
    self.mediaType = mediaType
    self.data = data
    self.size = size
  }
}

/// What the share sheet shows after the answer (task 12 in docs/plan.md): with a circle, the answer
/// asks for the next screenshot, so she goes one press at a time and the next one checks the press.
public enum ShareConsult {
  public static let askNext = "押せたらもう一度見せて"

  public static func reply(for answer: ConsultAnswer) -> String {
    guard answer.tap != nil else { return answer.reply }
    let trimmed = answer.reply.replacingOccurrences(of: "[。、\\s]+$", with: "", options: .regularExpression)
    return "\(trimmed)。\(askNext)"
  }

  /// Where the circle goes on the image she shared, or nil when there is none or it is off the image.
  public static func circle(for answer: ConsultAnswer, sent: PixelSize, original: PixelSize) -> PixelPoint? {
    guard let tap = answer.tap else { return nil }
    return CoordinateMapper.original(x: tap.x, y: tap.y, sent: sent, original: original)
  }
}
