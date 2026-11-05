import Testing

@testable import MimamoriCore

@Suite("SmileScorer")
struct SmileScorerTests {
  typealias Key = SmileScorer.Key

  private func shapes(
    left: Float, right: Float, cheekLeft: Float = 0.4, cheekRight: Float = 0.4
  ) -> [String: Float] {
    [
      Key.mouthSmileLeft: left, Key.mouthSmileRight: right, Key.cheekSquintLeft: cheekLeft,
      Key.cheekSquintRight: cheekRight,
    ]
  }

  @Test("口角が両方高く、頬も上がっていれば笑顔")
  func bothCornersAndCheeks() {
    let scorer = SmileScorer()
    #expect(scorer.isSmile(shapes(left: 0.8, right: 0.7)))
    #expect((scorer.score(shapes(left: 0.8, right: 0.7)) ?? 0) > 0.5)
  }

  @Test("口角が片方だけ高いなら笑顔ではない")
  func oneCornerOnly() {
    let scorer = SmileScorer()
    #expect(!scorer.isSmile(shapes(left: 0.9, right: 0.05)))
    #expect(!scorer.isSmile(shapes(left: 0.05, right: 0.9)))
  }

  @Test("口角が高くても頬が上がっていなければ笑顔ではない")
  func cheeksDown() {
    #expect(!SmileScorer().isSmile(shapes(left: 0.8, right: 0.8, cheekLeft: 0, cheekRight: 0)))
  }

  @Test(
    "値が1つでも欠けていれば笑顔ではなく、点数も出さない",
    arguments: [
      Key.mouthSmileLeft, Key.mouthSmileRight, Key.cheekSquintLeft, Key.cheekSquintRight,
    ])
  func missingValue(_ missing: String) {
    var values = shapes(left: 0.9, right: 0.9)
    values.removeValue(forKey: missing)
    let scorer = SmileScorer()
    #expect(!scorer.isSmile(values))
    #expect(scorer.score(values) == nil)
  }

  @Test("空の辞書は笑顔ではない")
  func empty() {
    #expect(!SmileScorer().isSmile([:]))
  }

  @Test("数でない値(NaN)は欠けたものとして扱う")
  func notANumber() {
    #expect(!SmileScorer().isSmile(shapes(left: .nan, right: 0.9)))
  }

  @Test("笑顔が決まった回数続いて初めて撮る。途中で崩れたら数え直す")
  func heldForFrames() {
    var gate = SmileGate(framesNeeded: 3)
    let smile = shapes(left: 0.8, right: 0.8)
    let neutral = shapes(left: 0.1, right: 0.1)
    #expect(gate.feed(smile) == nil)
    #expect(gate.feed(smile) == nil)
    #expect(gate.feed(neutral) == nil)
    #expect(gate.feed(smile) == nil)
    #expect(gate.feed(smile) == nil)
    let fired = gate.feed(smile)
    #expect(fired != nil)
    // Fires once; a smile that goes on does not take a second photo.
    #expect(gate.feed(smile) == nil)
  }
}
