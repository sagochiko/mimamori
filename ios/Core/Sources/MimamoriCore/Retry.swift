/// Tries a step that can fail for a moment (closing the audio session while the speech synthesizer is
/// still stopping) a few more times, waiting between tries, as long as it is still wanted.
public enum Retry {
  /// Runs `attempt`; after a failure, waits `delays[i]` and tries again, while `stillWanted()` holds.
  /// Each failure is passed to `failed` with its try number (from 1). A cancelled wait ends the
  /// retries. True when a try succeeded.
  @MainActor
  @discardableResult
  public static func run(
    delays: [Duration],
    stillWanted: () -> Bool,
    sleep: (Duration) async throws -> Void,
    failed: (any Error, Int) -> Void,
    attempt: () throws -> Void
  ) async -> Bool {
    var number = 1
    while true {
      do {
        try attempt()
        return true
      } catch {
        failed(error, number)
      }
      guard number <= delays.count else { return false }
      do {
        try await sleep(delays[number - 1])
      } catch {
        return false
      }
      guard stillWanted() else { return false }
      number += 1
    }
  }
}
