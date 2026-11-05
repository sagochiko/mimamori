import AVFoundation
import Foundation
import MimamoriCore
import os

/// Reads the AI's answer to a voice consultation aloud on the protected person's iPhone, with the
/// normal Japanese system voice, when 「読み上げ」 is on in Settings > みまもり (off by default, #115). Family members do not send her messages through the app; when they
/// want to talk to her, they call.
///
/// Other apps' sound (the radio, a video) is lowered while the session is active and stays lowered
/// until the session is deactivated (AVAudioSession.h, AVAudioSessionCategoryOptionDuckOthers), so the
/// session is released after the last line ends or is cancelled, telling the other app it may go on.
@MainActor
final class ReplySpeaker: NSObject, AVSpeechSynthesizerDelegate {
  private let synthesizer = AVSpeechSynthesizer()
  private var session = SpeechSession<ObjectIdentifier>()
  private var releasing: Task<Void, Never>?
  private static let log = Logger(subsystem: "com.sagochiko.mimamori", category: "speech")

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func speak(_ lines: [String]) {
    guard !lines.isEmpty else { return }
    releasing?.cancel()
    // .playback so the answer is heard even with the ring/silent switch on silent.
    try? AVAudioSession.sharedInstance().setCategory(
      .playback, mode: .spokenAudio, options: [.duckOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    let utterances = lines.map { line in
      let utterance = AVSpeechUtterance(string: line)
      utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
      utterance.postUtteranceDelay = 0.4
      return utterance
    }
    session.queued(utterances.map(ObjectIdentifier.init))
    for utterance in utterances { synthesizer.speak(utterance) }
  }

  /// Stops reading and leaves the audio session to the microphone, which sets it up itself. A release
  /// still pending from an earlier line is cancelled, so it cannot switch the recording off.
  func handOver() {
    releasing?.cancel()
    releasing = nil
    synthesizer.stopSpeaking(at: .immediate)
    _ = session.stopped()
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor in self.ended(id) }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor in self.ended(id) }
  }

  private func ended(_ id: ObjectIdentifier) {
    if session.ended(id) { release() }
  }

  /// Closing can fail while the synthesizer is still stopping (right after a reading was cut short), so a
  /// failure is logged and tried again a little later, unless a new answer started reading meanwhile.
  private func release() {
    releasing?.cancel()
    releasing = Task { [weak self] in
      // A new answer that starts reading at once cancels this before it runs.
      guard !Task.isCancelled, self?.session.isIdle == true else { return }
      await Retry.run(
        delays: [.milliseconds(300), .seconds(1)],
        stillWanted: { self?.session.isIdle ?? false },
        sleep: { try await Task.sleep(for: $0) },
        failed: { error, attempt in
          let code = (error as NSError).code
          Self.log.error("audio session deactivation failed, try \(attempt), code \(code)")
        },
        attempt: { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) })
    }
  }
}
