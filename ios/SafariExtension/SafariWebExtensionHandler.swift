import SafariServices

/// Stub until task 9. Page checks go from the content script straight to the server, so the native
/// side only answers with an empty message for now.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: [String: String]()]
    context.completeRequest(returningItems: [response])
  }
}
