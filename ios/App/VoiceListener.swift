import AVFoundation
import MimamoriCore
import Speech

/// Turns the protected person's voice into text on the iPhone (Speech, ja-JP, on-device only), so the
/// voice itself never leaves the phone. A thin adapter: when to start, stop, and send is decided by
/// `VoiceConsult` in Core.
///
/// Checked on the author's iPhone 16 on 2026年11月3日: on-device ja-JP recognition worked in airplane
/// mode and returned text in 0.04 s (docs/design.md, 初日に実機で確かめること).
@MainActor
final class VoiceListener {
  enum Event {
    /// The microphone and the recognizer are running (after the permission sheets, the first time).
    case started
    case partial(String)
    case final(String)
    /// How loud one buffer of the microphone's input was (root mean square, full scale 1), for the
    /// dots of the recording field (#224). Used on the screen only; never kept or sent.
    case level(Double)
    case failed(ConsultFailure)
  }

  var onEvent: ((Event) -> Void)?

  private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  /// Bumped on every start, so a late callback from an earlier recognition is ignored.
  private var generation = 0

  func start() async {
    generation += 1
    let current = generation
    guard await Self.permitted() else { return fail(.permissionDenied, generation: current) }
    guard current == generation else { return }
    guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
      return fail(.unavailable, generation: current)
    }
    do {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.record, mode: .measurement, options: [.duckOthers])
      try audio.setActive(true, options: .notifyOthersOnDeactivation)

      let request = SFSpeechAudioBufferRecognitionRequest()
      // Never send the voice to a server: if the on-device model is missing, this fails instead.
      request.requiresOnDeviceRecognition = true
      request.shouldReportPartialResults = true
      request.taskHint = .dictation
      Self.feed(engine.inputNode, into: request) { [weak self] rms in
        Task { @MainActor in
          guard let self, current == self.generation, self.task != nil else { return }
          self.onEvent?(.level(rms))
        }
      }
      engine.prepare()
      try engine.start()
      self.request = request
      task = Self.recognize(with: recognizer, request: request) {
        [weak self] text, isFinal, failed in
        Task { @MainActor in
          self?.handle(text: text, isFinal: isFinal, failed: failed, generation: current)
        }
      }
      onEvent?(.started)
    } catch {
      fail(.unavailable, generation: current)
    }
  }

  /// Ends the audio. The recognizer then delivers its final result through `onEvent`.
  func stop() {
    stopAudio()
    request?.endAudio()
  }

  /// The trash button: ends the audio and the recognition at once, and drops whatever would still
  /// come from them. A `start()` still waiting on the permission sheets stops at its next check.
  func cancel() {
    generation += 1
    teardown()
  }

  private func handle(text: String?, isFinal: Bool, failed: Bool, generation current: Int) {
    guard current == generation, task != nil else { return }
    if let text, isFinal {
      teardown()
      onEvent?(.final(text))
    } else if failed {
      // Most often "no speech detected" after the silence stop. Anything already heard is still sent.
      teardown()
      onEvent?(.failed(.notHeard))
    } else if let text {
      onEvent?(.partial(text))
    }
  }

  private func fail(_ failure: ConsultFailure, generation current: Int) {
    guard current == generation else { return }
    teardown()
    onEvent?(.failed(failure))
  }

  private func stopAudio() {
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
  }

  private func teardown() {
    stopAudio()
    task?.cancel()
    task = nil
    request = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // The tap and the recognition callbacks run on other threads. They are made in nonisolated
  // functions so they do not inherit the main actor, which Swift 6 would check at run time.

  nonisolated private static func feed(
    _ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest,
    level: @escaping @Sendable (Double) -> Void
  ) {
    nonisolated(unsafe) let request = request
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
      buffer, _ in
      request.append(buffer)
      level(rms(of: buffer))
    }
  }

  /// The root mean square of the first channel. The samples stay here; only this one number leaves.
  nonisolated private static func rms(of buffer: AVAudioPCMBuffer) -> Double {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    let count = Int(buffer.frameLength)
    var sum: Float = 0
    for i in 0..<count { sum += samples[i] * samples[i] }
    return Double((sum / Float(count)).squareRoot())
  }

  nonisolated private static func recognize(
    with recognizer: SFSpeechRecognizer,
    request: SFSpeechAudioBufferRecognitionRequest,
    report: @escaping @Sendable (String?, Bool, Bool) -> Void
  ) -> SFSpeechRecognitionTask {
    recognizer.recognitionTask(with: request) { result, error in
      report(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
    }
  }

  /// Speech recognition and the microphone, asked for the first time the microphone is pressed.
  /// Nonisolated for the same reason as above: TCC calls the speech answer back on a background
  /// queue, and when this closure inherited the main actor, Swift's run-time check stopped the app
  /// right after the permission sheet (author's iPhone, iOS 27.2, 2026年11月4日).
  nonisolated private static func permitted() async -> Bool {
    let speech = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { @Sendable status in
        continuation.resume(returning: status)
      }
    }
    guard speech == .authorized else { return false }
    return await AVAudioApplication.requestRecordPermission()
  }
}
