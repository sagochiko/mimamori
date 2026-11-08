import Foundation

/// One step of turning on an extension in iPhone Settings: the screenshot with a red ring on where
/// to tap (an asset name in the app's catalog), and the words of that tap.
public struct ExtensionGuideStep: Equatable, Sendable {
  public let image: String?
  public let caption: String

  public init(image: String?, caption: String) {
    self.image = image
    self.caption = caption
  }
}

/// The Safari extension and the SMS filter only work once she turns them on in iPhone Settings
/// (#287). Her settings screen lists both; each opens these steps and a button to Settings.
///
/// Shot on the iOS 26.5 "mimamori mother" simulator, and the captions use the words on those screens.
/// The simulator's Settings > Apps > Messages screen stayed blank, so the SMS filter's last step has
/// no picture and does not quote a row name it could not read. The Safari switch could not be flipped
/// there either, so the last Safari step (allowing the extension on websites, without which its
/// content script never runs) has no picture and names only the "アクセス権" heading shot above it.
public enum ExtensionGuide: String, CaseIterable, Sendable, Identifiable {
  case safari
  case sms

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .safari: "Safari の機能拡張"
    case .sms: "SMS の振り分け"
    }
  }

  public var steps: [ExtensionGuideStep] {
    switch self {
    case .safari:
      [
        ExtensionGuideStep(image: "guide-settings-apps", caption: "「アプリ」を押す"),
        ExtensionGuideStep(image: "guide-apps-safari", caption: "「Safari」を押す"),
        ExtensionGuideStep(image: "guide-safari-extensions", caption: "「機能拡張」を押す"),
        ExtensionGuideStep(image: "guide-extensions-mimamori", caption: "「mimamori」を押す"),
        ExtensionGuideStep(image: "guide-extension-allow", caption: "「機能拡張を許可」をオンにする"),
        ExtensionGuideStep(image: nil, caption: "「アクセス権」の下に出る行を押して「許可」を選ぶ"),
      ]
    case .sms:
      [
        ExtensionGuideStep(image: "guide-settings-apps", caption: "「アプリ」を押す"),
        ExtensionGuideStep(image: "guide-apps-messages", caption: "「メッセージ」を押す"),
        ExtensionGuideStep(image: nil, caption: "迷惑メッセージを振り分ける行を開いて「みまもり」を選ぶ"),
      ]
    }
  }

  /// What VoiceOver reads for a step's picture: its number and the tap.
  public func spokenLabel(at index: Int) -> String {
    "\(index + 1)番目、\(steps[index].caption)"
  }
}
