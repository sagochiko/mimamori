import IdentityLookup

/// Stub until task 5. Until the server answers, every message is delivered as usual (`.none`):
/// sending a genuine message (an auth code, a real delivery notice) to junk is the worse mistake.
final class MessageFilterExtension: ILMessageFilterExtension, ILMessageFilterQueryHandling {
  func handle(
    _ queryRequest: ILMessageFilterQueryRequest,
    context: ILMessageFilterExtensionContext,
    completion: @escaping (ILMessageFilterQueryResponse) -> Void
  ) {
    let response = ILMessageFilterQueryResponse()
    response.action = .none
    completion(response)
  }
}
