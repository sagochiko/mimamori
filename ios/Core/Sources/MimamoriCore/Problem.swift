import Foundation

/// What the person is told when a call fails. A 401 shows nothing: role selection appears instead.
public enum Problem: Equatable, Sendable {
  /// The invite code was not accepted. The server answers 404 for unknown, used, and expired codes.
  case badCode
  /// Anything else: offline, server down, or a request the server refused.
  case unreachable

  public init?(_ error: any Error, joining: Bool) {
    switch error {
    case APIError.unauthorized: return nil
    case APIError.http(status: 404) where joining: self = .badCode
    default: self = .unreachable
    }
  }
}
