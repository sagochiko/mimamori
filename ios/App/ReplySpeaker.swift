import AVFoundation
import Foundation
import MimamoriCore
import os

/// Reads family replies aloud on the protected person's iPhone with the normal Japanese system voice.
/// Personal Voice is not used: it cannot be made in Japanese, and the AI's answers use the same
/// normal voice, so "it sounds like family" never becomes a reason to trust a voice.
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
    // .playback so a reply is heard even with the ring/silent switch on silent.
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

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    if session.stopped() { release() }
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

  /// Closing can fail while the synthesizer is still stopping (right after "もう一度" stops it), so a
  /// failure is logged and tried again a little later, unless a new reply started reading meanwhile.
  private func release() {
    releasing?.cancel()
    releasing = Task { [weak self] in
      // "もう一度" stops and speaks again at once; the new reading cancels this before it runs.
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

/// Which replies were already read aloud, kept on this device.
struct UserDefaultsSpokenStore: SpokenStore {
  private let key = "mimamori.spokenRelayIds"

  func load() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
  }

  func save(_ ids: Set<String>) {
    UserDefaults.standard.set(Array(ids), forKey: key)
  }
}

/// The protected person's phone number for "電話する", entered on a family member's iPhone.
/// Kept only on this device; never sent to the server.
enum ProtectedPhoneStore {
  private static let key = "mimamori.protectedPhone"

  static func load() -> PhoneNumber? {
    UserDefaults.standard.string(forKey: key).flatMap(PhoneNumber.init)
  }

  static func save(_ number: PhoneNumber) {
    UserDefaults.standard.set(number.digits, forKey: key)
  }
}
