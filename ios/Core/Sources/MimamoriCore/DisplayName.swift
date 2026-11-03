import Foundation

/// The name shown to the family. The server trims it and allows up to 40 UTF-16 code units
/// (JavaScript `length`), so the app counts the same way and never cuts a character in half.
public enum DisplayName {
  public static let maxUTF16 = 40

  /// Cuts typed text to the limit, whole characters only.
  public static func limit(_ typed: String) -> String {
    var count = 0
    var kept = ""
    for character in typed {
      count += character.utf16.count
      if count > maxUTF16 { break }
      kept.append(character)
    }
    return kept
  }

  public static func trimmed(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func isValid(_ name: String) -> Bool {
    let name = trimmed(name)
    return !name.isEmpty && name.utf16.count <= maxUTF16
  }
}
