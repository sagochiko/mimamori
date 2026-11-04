import Foundation
import MimamoriCore
import Observation
import UIKit
import UserNotifications

/// The observable face of `Session` (in Core, where the routing is tested). It mirrors the route and
/// turns failures into a short alert.
@MainActor
@Observable
final class AppModel {
  private(set) var route: AppRoute
  private(set) var invite: Invite?
  private(set) var isBusy = false
  var problem: Problem?
  /// The family's recent cases (`GET /cases`), newest first.
  private(set) var cases: [Case] = []
  /// Bumped once a minute while a home screen is showing, so time-based text (the 30-minute
  /// "家族から返事がまだ") changes without a new answer from the server.
  private(set) var now = Date.now

  /// The voice consultation on the protected person's screen.
  private(set) var voice = VoiceConsult()
  /// "さっきの電話、大丈夫だった？" while a long call waits for an answer.
  private(set) var followUpPrompt: String?

  @ObservationIgnored private let session: Session
  @ObservationIgnored private lazy var speaker = ReplySpeaker()
  @ObservationIgnored private lazy var listener: VoiceListener = {
    let listener = VoiceListener()
    listener.onEvent = { [weak self] event in self?.listened(event) }
    return listener
  }()
  @ObservationIgnored private var silenceWatch: Task<Void, Never>?
  @ObservationIgnored private let followUp = CallFollowUp(store: UserDefaultsCallFollowUpStore())

  init(
    store: any DeviceKeyStore = KeychainDeviceKeyStore(),
    transport: any HTTPTransport = URLSessionTransport(),
    baseURL: URL = AppConfig.apiBaseURL,
    marker: any InstallMarkerStore = AppModel.installMarker
  ) {
    let session = Session(
      baseURL: baseURL, transport: transport, store: store, marker: marker,
      isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable })
    self.session = session
    self.route = session.route
    session.onRouteChange = { [weak self] route in
      self?.route = route
      if route == .chooseRole {
        self?.invite = nil
        self?.cases = []
      }
    }
  }

  /// An empty file in Application Support: deleted with the app, and checkable while locked.
  nonisolated static let installMarker = FileInstallMarker(
    url: URL.applicationSupportDirectory.appending(path: "mimamori-installed"))

  /// Re-reads the stored key: after the first unlock following a reboot, and whenever the app
  /// comes to the front.
  func refresh() {
    session.refresh()
  }

  /// The model the app runs with. Debug builds launched with `-mimamori-stub` use canned answers.
  static func live() -> AppModel {
    #if DEBUG
      if ScreenshotStubTransport.isRequested {
        return AppModel(
          store: InMemoryDeviceKeyStore(), transport: ScreenshotStubTransport(), marker: ScreenshotStubTransport.marker)
      }
    #endif
    return AppModel()
  }

  func createFamily(displayName: String) async {
    await run(joining: false) { try await $0.createFamily(displayName: displayName) }
    if route != .chooseRole { await requestPushIfJoined() }
  }

  func join(code: InviteCode, role: Role, displayName: String) async {
    await run(joining: true) { try await $0.join(code: code, role: role, displayName: displayName) }
    if route != .chooseRole { await requestPushIfJoined() }
  }

  func createInvite() async {
    await run(joining: false) { [weak self] session in
      let invite = try await session.createInvite()
      self?.invite = invite
    }
  }

  // MARK: Cases

  var familyCards: [FamilyCard] {
    cases.map { FamilyCard($0) }
  }

  var protectedNotices: [ProtectedNotice] {
    ProtectedNotice.notices(from: cases, now: now)
  }

  /// Reloads the cases. Quiet on failure: the screen keeps what it had and the next refresh tries again.
  /// Nothing is read aloud: only the answer to her own consultation is, so a reload cannot cut in while
  /// she is talking.
  func loadCases() async {
    guard route != .chooseRole else { return }
    now = .now
    guard let fresh = try? await session.cases() else { return }
    cases = fresh
  }

  /// Every minute while the screen is showing. Cancelled with the view's task.
  func keepCasesFresh() async {
    while !Task.isCancelled {
      await loadCases()
      try? await Task.sleep(for: .seconds(60))
    }
  }

  // MARK: Voice consultation

  /// The big microphone: starts listening, or stops it.
  func micTapped() {
    if case .listening = voice.phase {} else {
      followUp.consultStarted()
      followUpPrompt = nil
    }
    apply(voice.micTapped(at: .now))
  }

  private func listened(_ event: VoiceListener.Event) {
    switch event {
    case .started: apply(voice.listeningStarted(at: .now))
    case .partial(let text): apply(voice.heard(text, isFinal: false, at: .now))
    case .final(let text): apply(voice.heard(text, isFinal: true, at: .now))
    case .failed(let failure): apply(voice.listeningFailed(failure))
    }
  }

  private func apply(_ effects: [ConsultEffect]) {
    for effect in effects {
      switch effect {
      case .stopSpeaking:
        speaker.handOver()
      case .startListening:
        #if DEBUG
          if ScreenshotStubTransport.isRequested, let heard = ScreenshotStubTransport.heardText {
            apply(voice.heard(heard, isFinal: true, at: .now))
            continue
          }
        #endif
        // The silence clock starts when the listener reports .started, not here: the first time,
        // the permission sheets come first (VoiceConsult.listeningStarted).
        watchSilence()
        Task { await listener.start() }
      case .stopListening:
        listener.stop()
      case .send(let text):
        silenceWatch?.cancel()
        Task { await send(text) }
      case .speak(let text):
        speaker.speak([text])
      }
    }
    if case .listening = voice.phase {} else { silenceWatch?.cancel() }
  }

  /// Twice a second while listening, so listening ends on its own when she stops talking.
  private func watchSilence() {
    silenceWatch?.cancel()
    silenceWatch = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, !Task.isCancelled else { return }
        self.apply(self.voice.tick(at: .now))
      }
    }
  }

  private func send(_ text: String) async {
    do {
      let answer = try await session.consult(text: text)
      apply(voice.answered(answer))
      // The case shows up: "家族に伝えました", or "家族に届いていません" while no family device took it.
      if answer.handoff { await loadCases() }
    } catch {
      voice.sendFailed()
    }
  }

  // MARK: Call follow-up

  /// The single entry for whatever learns that a call ended (#25 decides what that is).
  func callEnded(_ call: EndedCall) async {
    switch followUp.callEnded(call) {
    case .notifyNow:
      await CallFollowUpNotifier.post()
      refreshFollowUp()
    case .askOnNextOpen:
      refreshFollowUp()
    case .nothing:
      break
    }
  }

  /// When the screen appears or the app comes to the front.
  func refreshFollowUp() {
    followUpPrompt = followUp.promptToShow(at: .now)
  }

  /// "大丈夫": nothing else happens.
  func followUpFine() {
    followUp.answeredFine()
    followUpPrompt = nil
  }

  /// "解決", from any family member. The server tells the rest of the family.
  func resolve(_ item: Case) async {
    await run(joining: false) { [weak self] session in
      let updated = try await session.resolve(caseId: item.id)
      self?.replace(updated)
    }
  }

  private func replace(_ item: Case) {
    if let i = cases.firstIndex(where: { $0.id == item.id }) { cases[i] = item }
  }

  /// Asks for notification permission once the person has joined, then registers with APNs.
  func requestPushIfJoined() async {
    guard route != .chooseRole else { return }
    let granted =
      (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    if granted { UIApplication.shared.registerForRemoteNotifications() }
  }

  /// No alert on failure: the token is sent again on the next launch. A 401 still ends at role
  /// selection, through `Session`.
  func didReceiveAPNs(token: Data) async {
    #if DEBUG
      let environment = APNsEnvironment.sandbox
    #else
      let environment = APNsEnvironment.production
    #endif
    try? await session.registerAPNs(token: token, environment: environment)
  }

  private func run(joining: Bool, _ body: (Session) async throws -> Void) async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await body(session)
      problem = nil
    } catch {
      problem = Problem(error, joining: joining)
    }
  }
}
