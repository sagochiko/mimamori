import Foundation
import Testing

@testable import MimamoriCore

// The steps in her settings for turning on the Safari extension and the SMS filter (#287). The
// pictures were shot on the iOS 26.5 "mimamori mother" simulator; the captions use the words on them.
@Suite("拡張機能をオンにする手順")
struct ExtensionGuideTests {
  @Test("行の名札は2つ")
  func titles() {
    #expect(ExtensionGuide.allCases.map(\.title) == ["Safari の機能拡張", "SMS の振り分け"])
  }

  @Test("Safari は6段で、5段目までは撮った画面の言葉のとおり、最後はサイトの許可で画像が無い")
  func safariSteps() {
    let steps = ExtensionGuide.safari.steps
    #expect(
      steps.map(\.caption) == [
        "「アプリ」を押す",
        "「Safari」を押す",
        "「機能拡張」を押す",
        "「mimamori」を押す",
        "「機能拡張を許可」をオンにする",
        "「アクセス権」の下に出る行を押して「許可」を選ぶ",
      ])
    #expect(steps.prefix(5).allSatisfy { $0.image != nil })
    #expect(steps[5].image == nil)
  }

  @Test("SMS は「アプリ」「メッセージ」までが画像で、その先は画像が無い")
  func smsSteps() {
    let steps = ExtensionGuide.sms.steps
    #expect(steps.count == 3)
    #expect(steps.prefix(2).map(\.caption) == ["「アプリ」を押す", "「メッセージ」を押す"])
    #expect(steps.prefix(2).allSatisfy { $0.image != nil })
    #expect(steps[2].image == nil)
    #expect(steps[2].caption.contains("みまもり"))
  }

  @Test("読み上げは番号と押す言葉を読む")
  func spokenLabel() {
    let step = ExtensionGuide.safari.steps[0]
    #expect(ExtensionGuide.safari.spokenLabel(at: 0) == "1番目、\(step.caption)")
  }

  @Test("画像の名前はすべてアセットカタログにある")
  func imagesExist() {
    let assets = URL(filePath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "App/Assets.xcassets")
    let names = ExtensionGuide.allCases.flatMap(\.steps).compactMap(\.image)
    #expect(!names.isEmpty)
    for name in names {
      let png = assets.appending(path: "\(name).imageset/\(name).png")
      #expect(FileManager.default.fileExists(atPath: png.path()), "\(name)")
    }
  }
}
