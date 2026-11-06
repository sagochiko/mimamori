import Foundation
import MimamoriCore

enum AppConfig {
  /// From Info.plist `MimamoriAPIBaseURL`, which is `https://$(MIMAMORI_API_HOST)` (ios/Config/Shared.xcconfig).
  static let apiBaseURL: URL = {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "MimamoriAPIBaseURL") as? String,
      let url = URL(string: text)
    else { preconditionFailure("MimamoriAPIBaseURL is missing from Info.plist") }
    return url
  }()

  /// Whether this is the judges' build: Info.plist `MimamoriSMSFamilyToken` is `demo` (#100). The
  /// mother's build carries her family's token there, so the tour never shows on her iPhone.
  static let isDemo: Bool = DemoMode.isOn(
    smsFamilyToken: Bundle.main.object(forInfoDictionaryKey: "MimamoriSMSFamilyToken") as? String)
}
