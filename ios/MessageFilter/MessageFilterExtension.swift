import IdentityLookup
import MimamoriCore

/// Sends every SMS from an unknown sender to the server named in Info.plist
/// (ILMessageFilterExtensionNetworkURL, set per build in ios/Config) and turns its reply into an action.
/// The extension cannot reach the network itself or write to the app's shared container (Apple,
/// "SMS and MMS Message Filtering"), so it decides nothing on its own. Anything other than a clear
/// "junk" from the server, failures included, delivers the message as usual (`.none`): sending a
/// genuine message (an auth code, a real delivery notice) to junk is the worse mistake.
final class MessageFilterExtension: ILMessageFilterExtension, ILMessageFilterQueryHandling {
  func handle(
    _ queryRequest: ILMessageFilterQueryRequest,
    context: ILMessageFilterExtensionContext,
    completion: @escaping (ILMessageFilterQueryResponse) -> Void
  ) {
    // IdentityLookup's completion is not marked Sendable; the system calls it once, from its own queue.
    nonisolated(unsafe) let completion = completion
    context.deferQueryRequestToNetwork { networkResponse, _ in
      let verdict = SMSFilterReply.verdict(
        statusCode: networkResponse?.urlResponse.statusCode,
        data: networkResponse?.data
      )
      let response = ILMessageFilterQueryResponse()
      response.action = Self.action(for: verdict)
      completion(response)
    }
  }

  private static func action(for verdict: SMSFilterVerdict) -> ILMessageFilterAction {
    switch verdict {
    case .junk: .junk
    case .none: .none
    }
  }
}
