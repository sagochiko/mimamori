import AuthenticationServices
import MimamoriCore
import UIKit

/// The thin adapter around ASWebAuthenticationSession for her Gmail grant. Google's consent screen runs
/// in the system browser sheet (Google refuses embedded web views), and the server's callback sends it
/// back to `mimamori://gmail?result=...`, which the session catches for itself.
@MainActor
enum GmailSignIn {
  /// The session must be held while it is showing.
  private static var current: ASWebAuthenticationSession?
  private static let anchor = Anchor()

  static func run(url: URL) async -> GmailConnectResult {
    await withCheckedContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url, callback: .customScheme(GmailConnectResult.callbackScheme)
      ) { callback, error in
        let result: GmailConnectResult =
          if let callback {
            GmailConnectResult(callback: callback)
          } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
            .denied
          } else {
            .failed
          }
        Task { @MainActor in current = nil }
        continuation.resume(returning: result)
      }
      session.presentationContextProvider = anchor
      // No cookies kept between grants: she signs in to her own account each time.
      session.prefersEphemeralWebBrowserSession = true
      current = session
      if !session.start() {
        current = nil
        continuation.resume(returning: .failed)
      }
    }
  }

  private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
      MainActor.assumeIsolated {
        UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap(\.windows)
          .first { $0.isKeyWindow } ?? ASPresentationAnchor()
      }
    }
  }
}
