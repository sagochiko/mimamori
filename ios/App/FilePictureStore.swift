import Foundation
import MimamoriCore

/// The screenshots she showed in her chat, shrunk (#243), one file each in a folder of Application
/// Support: kept like her conversation (`FileChatLogStore`), deleted with the app, never sent anywhere,
/// out of iCloud and computer backups, and written with complete file protection. `ChatKeeper` deletes
/// those no kept message names.
struct FilePictureStore: ChatPictureStore {
  let folder: URL

  static let standard = FilePictureStore(
    folder: URL.applicationSupportDirectory.appending(path: "chat-pictures", directoryHint: .isDirectory))

  func read(_ name: String) throws -> Data? {
    do {
      return try Data(contentsOf: url(name))
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    }
  }

  func write(_ data: Data, name: String) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var dir = folder
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try dir.setResourceValues(values)
    // .completeFileProtection is NSFileProtectionComplete; .atomic so a crash leaves no half file.
    var file = url(name)
    try data.write(to: file, options: [.atomic, .completeFileProtection])
    try file.setResourceValues(values)
  }

  func remove(_ name: String) throws {
    do {
      try FileManager.default.removeItem(at: url(name))
    } catch let error as CocoaError where error.code == .fileNoSuchFile {
      return
    }
  }

  func names() throws -> [String] {
    do {
      return try FileManager.default.contentsOfDirectory(atPath: folder.path)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return []
    }
  }

  /// Only a plain file name inside the folder: a name with a path in it is not followed.
  private func url(_ name: String) -> URL {
    folder.appending(path: (name as NSString).lastPathComponent, directoryHint: .notDirectory)
  }
}
