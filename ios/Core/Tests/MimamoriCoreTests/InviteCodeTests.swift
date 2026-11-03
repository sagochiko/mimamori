import Testing

@testable import MimamoriCore

@Suite("招待のコード")
struct InviteCodeTests {
  @Test("6桁の半角数字は受け付ける", arguments: ["123456", "000000", "987654"])
  func acceptsSixDigits(raw: String) {
    #expect(InviteCode(raw)?.value == raw)
  }

  @Test(
    "6桁の半角数字以外は受け付けない",
    arguments: [
      "",
      "12345",  // 5桁
      "1234567",  // 7桁
      "12a456",  // 英字
      "123 456",  // 空白
      " 123456",  // 前の空白
      "１２３４５６",  // 全角の数字
      "١٢٣٤٥٦",  // アラビア・インド数字
      "12345６",
      "-12345",
      "12.456",
    ]
  )
  func rejectsOthers(raw: String) {
    #expect(InviteCode(raw) == nil)
  }

  @Test("入力の途中は、半角数字だけを6桁まで残す")
  func sanitizesTyping() {
    #expect(InviteCode.sanitize("12a3 4") == "1234")
    #expect(InviteCode.sanitize("12345678") == "123456")
  }

  @Test("貼り付けた全角の数字は半角に直して残す")
  func normalizesFullWidthDigits() {
    #expect(InviteCode.sanitize("４８２９１３") == "482913")
    #expect(InviteCode.sanitize("１２3") == "123")
    #expect(InviteCode.sanitize("４８２　９１３") == "482913")
    #expect(InviteCode(InviteCode.sanitize("４８２９１３")) != nil)
  }

  @Test("ほかの文字の数字は数字として扱わない")
  func dropsOtherScripts() {
    #expect(InviteCode.sanitize("١٢٣٤٥٦") == "")
  }
}
