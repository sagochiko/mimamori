import Testing

@testable import MimamoriCore

@Suite("ホームのメニュー")
struct HomeMenuTests {
  @Test("家族の画面には設定(#282)、「この iPhone を外す」、「家族を削除」が並ぶ")
  func familyCanLeave() {
    #expect(HomeMenuItem.items(for: .familyHome) == [.settings, .leaveDevice, .deleteFamily])
  }

  @Test("見守られる人の画面には「この iPhone を外す」を出さない(設定と「家族を削除」だけ)")
  func protectedCannotLeave() {
    let items = HomeMenuItem.items(for: .protectedHome)
    #expect(!items.contains(.leaveDevice))
    #expect(items == [.settings, .deleteFamily])
  }

  @Test("役を選ぶ画面にはメニューの項目が無い")
  func roleSelectionHasNone() {
    #expect(HomeMenuItem.items(for: .chooseRole).isEmpty)
  }
}
