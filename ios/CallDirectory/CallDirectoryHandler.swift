import CallKit

/// Stub until the list of scam numbers exists. Adds nothing, so no call is labelled yet.
final class CallDirectoryHandler: CXCallDirectoryProvider {
  override func beginRequest(with context: CXCallDirectoryExtensionContext) {
    context.completeRequest()
  }
}
