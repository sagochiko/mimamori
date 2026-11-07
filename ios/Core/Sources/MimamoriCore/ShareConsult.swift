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

  /// The server takes no more base64 than this (IMAGE_MAX_BASE64_CHARS in server/src/consult.ts).
  public static let maxBase64Characters = 3_000_000
  /// The JPEG qualities the share sheet and the chat's photo button try, best first, until one fits.
  public static let jpegQualities: [Double] = [0.85, 0.6, 0.4]

  /// Whether an encoded image of `byteCount` bytes is within what the server takes.
  public static func fitsServer(byteCount: Int) -> Bool {
    (byteCount + 2) / 3 * 4 <= maxBase64Characters
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

  /// What the server answers to an image with no words when it asks what she wants
  /// (server/src/consult-judge.ts, ASK_PICTURE_REPLY, #234).
  public static let askPicture = "この画面で何をしたい?"
  /// The share sheet has no field to answer in, so there she is sent to the app (review 1 of PR #237).
  public static let askInApp = "みまもりを開いて何をしたいか教えてね"

  /// The answer as the share extension shows it: `reply(for:)`, with the server's question about an
  /// image alone put as `askInApp`. The server's answer itself is unchanged.
  public static func extensionReply(for answer: ConsultAnswer) -> String {
    answer.reply == askPicture ? askInApp : reply(for: answer)
  }

  /// Where the circle goes on the image she shared, or nil when there is none or it is off the image.
  public static func circle(for answer: ConsultAnswer, sent: PixelSize, original: PixelSize) -> PixelPoint? {
    guard let tap = answer.tap else { return nil }
    return CoordinateMapper.original(x: tap.x, y: tap.y, sent: sent, original: original)
  }
}
