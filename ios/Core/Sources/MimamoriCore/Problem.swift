import Foundation

/// What the person is told when a call fails. A 401 shows nothing: role selection appears instead.
public enum Problem: Equatable, Sendable {
  /// The invite code was not accepted. The server answers 404 for unknown, used, and expired codes.
  case badCode
  /// Someone else accepted the case first ("(名前)が対応中").
  case taken(by: String)
  /// The case was already resolved.
  case resolved
  /// Anything else: offline, server down, or a request the server refused.
  case unreachable

  public init?(_ error: any Error, joining: Bool) {
    switch error {
    case APIError.unauthorized: return nil
    case APIError.http(status: 404) where joining: self = .badCode
    case APIError.conflict(code: "already_resolved", _): self = .resolved
    case APIError.conflict(_, assigneeName: let name?): self = .taken(by: name)
    default: self = .unreachable
    }
  }
}
