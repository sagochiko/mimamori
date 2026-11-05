import Foundation
import MimamoriCore
import SafariServices

/// The native side of the Safari extension. The background script (Resources/background.js) hands it
/// `{ type: "page", url, text }` with `browser.runtime.sendNativeMessage`, since content scripts cannot
/// message the native side themselves (Apple, "Messaging between the app and JavaScript in a Safari web
/// extension"). It sends `POST /page` with this device's key from the shared Keychain group and answers
/// `{ level: 1 | 2 }` or `{}`. The device key never reaches the JavaScript, so the extension needs no
/// host permission for the server.
///
/// The page's URL and text are data for the server's rules and are not logged here.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    let item = context.inputItems.first as? NSExtensionItem
    let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any] ?? [:]
    // NSExtensionContext is not Sendable; the system expects one completeRequest call, made here once.
    nonisolated(unsafe) let context = context
    guard let baseURL = Self.baseURL else {
      Self.complete(context, warning: nil)
      return
    }
    let checker = PageChecker(baseURL: baseURL, store: KeychainDeviceKeyStore())
    nonisolated(unsafe) let sent = message
    Task {
      let warning = await checker.check(sent)
      Self.complete(context, warning: warning)
    }
  }

  private static var baseURL: URL? {
    guard let text = Bundle.main.object(forInfoDictionaryKey: "MimamoriAPIBaseURL") as? String
    else { return nil }
    return URL(string: text)
  }

  private static func complete(_ context: NSExtensionContext, warning: PageWarning?) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: PageCheck.reply(for: warning)]
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
}
