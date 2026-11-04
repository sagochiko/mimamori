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
    case partial(String)
    case final(String)
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
      Self.feed(engine.inputNode, into: request)
      engine.prepare()
      try engine.start()
      self.request = request
      task = Self.recognize(with: recognizer, request: request) {
        [weak self] text, isFinal, failed in
        Task { @MainActor in
          self?.handle(text: text, isFinal: isFinal, failed: failed, generation: current)
        }
      }
    } catch {
      fail(.unavailable, generation: current)
    }
  }

  /// Ends the audio. The recognizer then delivers its final result through `onEvent`.
  func stop() {
    stopAudio()
    request?.endAudio()
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
    _ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest
  ) {
    nonisolated(unsafe) let request = request
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
      buffer, _ in
      request.append(buffer)
    }
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
  private static func permitted() async -> Bool {
    let speech = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
    }
    guard speech == .authorized else { return false }
    return await AVAudioApplication.requestRecordPermission()
  }
}
