import Foundation

/// Scores a smile from face blend shapes (task 13, "毎朝の笑顔"). The input is a plain dictionary of
/// blend shape names to values from 0 to 1, so this runs without ARKit; the App's camera turns
/// `ARFaceAnchor.blendShapes` into it, mapping each enum case to the names in `Key`.
///
/// A smile needs both mouth corners up and the cheeks raised. One corner alone is a smirk or a
/// twitch, and corners without cheeks are often a forced grin. A missing value is never a smile.
public struct SmileScorer: Sendable {
  public enum Key {
    public static let mouthSmileLeft = "mouthSmileLeft"
    public static let mouthSmileRight = "mouthSmileRight"
    public static let cheekSquintLeft = "cheekSquintLeft"
    public static let cheekSquintRight = "cheekSquintRight"
  }

  /// Each mouth corner must be at least this high.
  public var cornerThreshold: Float
  /// The two cheeks together, averaged, must be at least this high.
  public var cheekThreshold: Float

  public init(cornerThreshold: Float = 0.5, cheekThreshold: Float = 0.15) {
    self.cornerThreshold = cornerThreshold
    self.cheekThreshold = cheekThreshold
  }

  /// The average of the two mouth corners, or nil when any of the four values is missing or not a
  /// number.
  public func score(_ shapes: [String: Float]) -> Double? {
    guard let values = values(shapes) else { return nil }
    return Double((values.left + values.right) / 2)
  }

  public func isSmile(_ shapes: [String: Float]) -> Bool {
    guard let v = values(shapes) else { return false }
    return min(v.left, v.right) >= cornerThreshold
      && (v.cheekLeft + v.cheekRight) / 2 >= cheekThreshold
  }

  private func values(_ shapes: [String: Float]) -> (
    left: Float, right: Float, cheekLeft: Float, cheekRight: Float
  )? {
    guard let left = shapes[Key.mouthSmileLeft], let right = shapes[Key.mouthSmileRight],
      let cheekLeft = shapes[Key.cheekSquintLeft], let cheekRight = shapes[Key.cheekSquintRight],
      [left, right, cheekLeft, cheekRight].allSatisfy(\.isFinite)
    else { return nil }
    return (left, right, cheekLeft, cheekRight)
  }
}

/// Takes the photo only after the smile has held for a few frames in a row, so a twitch does not
/// count, and only once per gate.
public struct SmileGate: Sendable {
  public let framesNeeded: Int
  public let scorer: SmileScorer
  private var streak = 0
  private var fired = false

  /// ARKit's face tracking delivers about 60 updates a second; 8 is a little over a tenth of a second.
  public init(framesNeeded: Int = 8, scorer: SmileScorer = SmileScorer()) {
    self.framesNeeded = max(1, framesNeeded)
    self.scorer = scorer
  }

  /// The score to send with the photo when this frame completes a held smile, otherwise nil.
  public mutating func feed(_ shapes: [String: Float]) -> Double? {
    guard !fired else { return nil }
    guard scorer.isSmile(shapes) else {
      streak = 0
      return nil
    }
    streak += 1
    guard streak >= framesNeeded else { return nil }
    fired = true
    return scorer.score(shapes)
  }
}
