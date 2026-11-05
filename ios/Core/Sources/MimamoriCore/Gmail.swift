import Foundation

/// `GET /gmail/connect`: Google's consent screen for reading her mail, and when the current grant was
/// given (nil when there is none). Google ends a grant of a Testing app after 7 days.
public struct GmailGrant: Equatable, Sendable, Decodable {
  public let url: URL
  public let grantedAt: Date?

  public init(url: URL, grantedAt: Date?) {
    self.url = url
    self.grantedAt = grantedAt
  }

  /// The server tells the family to take it again 6 days after the grant; the button shows from then.
  public static let renewAfter: TimeInterval = 6 * 24 * 3600

  /// Whether her screen should offer the button: no grant yet, or one about to run out.
  public func needsGrant(now: Date) -> Bool {
    guard let grantedAt else { return true }
    return now.timeIntervalSince(grantedAt) >= Self.renewAfter
  }
}

/// Where Google's redirect leaves her browser: `mimamori://gmail?result=...` (the server's callback).
public enum GmailConnectResult: Equatable, Sendable {
  case connected
  case denied
  case failed

  /// The scheme the sign-in session waits for.
  public static let callbackScheme = "mimamori"

  public init(callback url: URL) {
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    guard url.scheme == Self.callbackScheme, url.host == "gmail" else {
      self = .failed
      return
    }
    switch parts?.queryItems?.first(where: { $0.name == "result" })?.value {
    case "connected": self = .connected
    case "denied": self = .denied
    default: self = .failed
    }
  }
}

extension APIClient {
  /// `GET /gmail/connect`. Protected member only (403 otherwise). Nil while the server has no Google
  /// client set up (503), so the app shows no button.
  public func gmailConnect() async throws -> GmailGrant? {
    do {
      return try await get("gmail/connect")
    } catch APIError.http(status: 503) {
      return nil
    }
  }
}
