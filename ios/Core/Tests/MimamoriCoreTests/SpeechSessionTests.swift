import Testing

@testable import MimamoriCore

/// The protected person's iPhone lowers other apps' sound while a reply is read, and must give it
/// back once the last line ends (ReplySpeaker in the app).
struct SpeechSessionTests {
  @Test func releasesOnlyAfterTheLastLineEnds() {
    var session = SpeechSession<Int>()
    session.queued([1, 2])

    #expect(session.ended(1) == false)
    #expect(session.ended(2) == true)
    #expect(session.isIdle)
  }

  @Test func aLineQueuedWhileSpeakingKeepsTheSessionUntilItEnds() {
    var session = SpeechSession<Int>()
    session.queued([1])
    session.queued([2])

    #expect(session.ended(1) == false)
    #expect(session.ended(2) == true)
  }

  @Test func stoppingReleasesAtOnceAndLateCallbacksDoNotReleaseANewLine() {
    // "もう一度" stops the current reading and starts a new one; the cancel callback for the old line
    // arrives after the new line was queued and must not end the new line's session.
    var session = SpeechSession<Int>()
    session.queued([1, 2])

    #expect(session.stopped() == true)
    session.queued([3])
    #expect(session.ended(1) == false)
    #expect(session.ended(2) == false)
    #expect(session.ended(3) == true)
  }

  @Test func stoppingWhenNothingPlaysReleasesNothing() {
    var session = SpeechSession<Int>()
    #expect(session.stopped() == false)
    #expect(session.ended(9) == false)
  }
}
