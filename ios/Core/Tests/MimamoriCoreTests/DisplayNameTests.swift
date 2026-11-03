import Testing

@testable import MimamoriCore

@Suite("名前の長さ")
struct DisplayNameTests {
  @Test("40文字までは、そのまま")
  func keepsUpToForty() {
    let forty = String(repeating: "あ", count: 40)
    #expect(DisplayName.limit(forty) == forty)
    #expect(DisplayName.limit("作者") == "作者")
  }

  @Test("41文字目からは切る")
  func cutsAtForty() {
    #expect(DisplayName.limit(String(repeating: "a", count: 41)) == String(repeating: "a", count: 40))
  }

  @Test("裏側と同じく UTF-16 で数え、絵文字を途中で切らない")
  func countsUTF16WithoutSplitting() {
    // 😀 is 2 UTF-16 units. 39 + 2 > 40, so the emoji is dropped whole.
    let name = String(repeating: "a", count: 39) + "😀"
    #expect(DisplayName.limit(name) == String(repeating: "a", count: 39))
    #expect(DisplayName.limit(String(repeating: "😀", count: 20)).utf16.count == 40)
  }

  @Test("前後の空白は数えない(裏側も trim してから数える)")
  func ignoresSurroundingSpaces() {
    let padded = "  " + String(repeating: "a", count: 40) + "  "
    #expect(DisplayName.isValid(padded))
    #expect(!DisplayName.isValid("   "))
    #expect(!DisplayName.isValid(String(repeating: "a", count: 41)))
  }
}
