import Foundation

/// What the person is told when a call fails. A 401 shows nothing: role selection appears instead.
public enum Problem: Equatable, Sendable {
  /// The invite code was not accepted. The server answers 404 for unknown, used, and expired codes.
  case badCode
  /// Anything else: offline, server down, or a request the server refused.
  case unreachable
  /// "家族を削除" did not finish. Nothing on this iPhone was deleted, and pressing again continues.
  case notDeleted
  /// "この iPhone を外す" did not finish. This iPhone is still in the family, and pressing again continues.
  case notLeft

  public init?(_ error: any Error, joining: Bool) {
    switch error {
    case APIError.unauthorized: return nil
    case APIError.http(status: 404) where joining: self = .badCode
    default: self = .unreachable
    }
  }

  /// For "この iPhone を外す": any failure is told as not removed, even offline. A 401 shows nothing:
  /// the key no longer works, so role selection appears instead.
  public init?(leaving error: any Error) {
    if case APIError.unauthorized = error { return nil }
    self = .notLeft
  }

  /// For "家族を削除": any failure is told as not deleted, even offline, since that is what matters
  /// to the person. A 401 shows nothing: role selection appears instead.
  public init?(deleting error: any Error) {
    if case APIError.unauthorized = error { return nil }
    self = .notDeleted
  }
}
