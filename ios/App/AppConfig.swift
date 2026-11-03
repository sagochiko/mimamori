import Foundation

enum AppConfig {
  /// From Info.plist `MimamoriAPIBaseURL`, which is `https://$(MIMAMORI_API_HOST)` (ios/Config/Shared.xcconfig).
  static let apiBaseURL: URL = {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "MimamoriAPIBaseURL") as? String,
      let url = URL(string: text)
    else { preconditionFailure("MimamoriAPIBaseURL is missing from Info.plist") }
    return url
  }()
}
