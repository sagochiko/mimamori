import Testing

@testable import MimamoriCore

/// Releasing the audio session can fail while the synthesizer is still stopping; ReplySpeaker tries
/// again a little later, unless a new reply started reading meanwhile.
@MainActor
struct RetryTests {
  struct Busy: Error {}

  @Test func succeedsAtOnceWithoutWaiting() async {
    var tries = 0
    var slept: [Duration] = []
    let ok = await Retry.run(
      delays: [.milliseconds(300), .seconds(1)], stillWanted: { true },
      sleep: { slept.append($0) }, failed: { _, _ in }, attempt: { tries += 1 })

    #expect(ok)
    #expect(tries == 1)
    #expect(slept.isEmpty)
  }

  @Test func triesAgainAfterTheDelayAndReportsEachFailure() async {
    var tries = 0
    var slept: [Duration] = []
    var failures: [Int] = []
    let ok = await Retry.run(
      delays: [.milliseconds(300), .seconds(1)], stillWanted: { true },
      sleep: { slept.append($0) }, failed: { _, n in failures.append(n) },
      attempt: {
        tries += 1
        if tries == 1 { throw Busy() }
      })

    #expect(ok)
    #expect(tries == 2)
    #expect(slept == [.milliseconds(300)])
    #expect(failures == [1])
  }

  @Test func givesUpAfterTheLastDelay() async {
    var tries = 0
    var failures: [Int] = []
    let ok = await Retry.run(
      delays: [.milliseconds(300), .seconds(1)], stillWanted: { true },
      sleep: { _ in }, failed: { _, n in failures.append(n) },
      attempt: {
        tries += 1
        throw Busy()
      })

    #expect(!ok)
    #expect(tries == 3)
    #expect(failures == [1, 2, 3])
  }

  @Test func stopsWhenNoLongerWanted() async {
    // A new reply started reading while waiting: closing the session now would cut it off.
    var tries = 0
    var wanted = true
    let ok = await Retry.run(
      delays: [.milliseconds(300)], stillWanted: { wanted },
      sleep: { _ in wanted = false }, failed: { _, _ in },
      attempt: {
        tries += 1
        throw Busy()
      })

    #expect(!ok)
    #expect(tries == 1)
  }

  @Test func stopsWhenTheWaitIsCancelled() async {
    var tries = 0
    let ok = await Retry.run(
      delays: [.milliseconds(300)], stillWanted: { true },
      sleep: { _ in throw CancellationError() }, failed: { _, _ in },
      attempt: {
        tries += 1
        throw Busy()
      })

    #expect(!ok)
    #expect(tries == 1)
  }
}
