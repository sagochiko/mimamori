import Foundation
import MimamoriCore

/// Her conversation in one file in Application Support: deleted with the app, never sent anywhere,
/// and written with complete file protection, so it cannot be read while the iPhone is locked.
/// `ChatKeeper` (Core) only writes after a read succeeded, so a locked launch does not replace it.
struct FileChatLogStore: ChatLogStore {
  let url: URL

  static let standard = FileChatLogStore(
    url: URL.applicationSupportDirectory.appending(path: "chat.json"))

  func read() throws -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    }
  }

  func write(_ data: Data) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    // .completeFileProtection is NSFileProtectionComplete; .atomic so a crash leaves the old file.
    try data.write(to: url, options: [.atomic, .completeFileProtection])
  }
}
