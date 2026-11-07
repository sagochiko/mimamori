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

  /// The consultation on the protected person's screen, by voice or in writing.
  private(set) var voice = VoiceConsult()
  /// The dots of the recording field (#224). Apart from `voice`, so the many updates a second
  /// redraw only the dots and not everything that reads the consultation.
  private(set) var levels = VoiceLevels()
  /// Her words from the stop button, waiting for the field to take them (`takeVoiceDraft`).
  private(set) var voiceDraft: String?
  /// Her conversation, kept on this iPhone only (#73).
  private(set) var chat: ChatKeeper
  /// The screenshot she showed last with the photo button (#221), in memory only, with the ring once
  /// the answer comes. Gone with her next consultation and when the app quits; never in `chat`.
  private(set) var shownPicture: ShownPicture?
  /// The screenshot she picked with the photo button, waiting on the field to go with her words
  /// (#234). In memory only, like `shownPicture`.
  private(set) var attachedPicture: ConsultPicture?
  /// `CallFollowUp.prompt` after a long call, until she closes it or starts talking.
  private(set) var followUpPrompt: String?
  /// "iPhoneの空きが残り0.8GB。一緒に空けよう" while free space is low (#19). The amount is read on
  /// this iPhone for this line only and never sent.
  private(set) var checkupPrompt: String?
  /// Everyone's smiles and replies (`GET /smiles`), newest first, with the hour her smile is expected by.
  private(set) var smileBoard = SmileBoard()
  /// Her Gmail grant (`GET /gmail/connect`): nil until read, and while the server has no Google client.
  private(set) var gmail: GmailGrant?
  /// Photos already fetched this run, by smile id. They never change, so they are not fetched again.
  @ObservationIgnored private var photoCache: [String: Data] = [:]

  @ObservationIgnored private let session: Session
  @ObservationIgnored private lazy var speaker = ReplySpeaker()
  @ObservationIgnored private lazy var listener: VoiceListener = {
    let listener = VoiceListener()
    listener.onEvent = { [weak self] event in self?.listened(event) }
    return listener
  }()
  @ObservationIgnored private var silenceWatch: Task<Void, Never>?
  #if DEBUG
    /// `-mimamori-stub-listening`: the made-up voice levels while the stub "listens".
    @ObservationIgnored private var stubLevels: Task<Void, Never>?
  #endif
  /// What goes to the server for `attachedPicture`, made when she picked it.
  @ObservationIgnored private var attachedImage: ConsultImage?
  @ObservationIgnored private let followUp = CallFollowUp(
    store: UserDefaultsCallFollowUpStore(), minimumDuration: AppModel.followUpMinimum)
  @ObservationIgnored private let checkup = CheckupPolicy(store: UserDefaultsCheckupStore())
  /// One heartbeat at a time, so two foregrounds in a row do not both pass the gate.
  @ObservationIgnored private var heartbeatWork: Task<Void, Never>?
  @ObservationIgnored private lazy var callWatcher = CallEndWatcher { [weak self] call in
    Task { await self?.callEnded(call) }
  }
  /// Rebuilds run one after another, so a slower one cannot put back requests a newer one removed.
  @ObservationIgnored private var checkInWork: Task<Void, Never>?
  #if DEBUG
    @ObservationIgnored private var postedDebugCheckIn = false
  #endif

  init(
    store: any DeviceKeyStore = KeychainDeviceKeyStore(),
    transport: any HTTPTransport = URLSessionTransport(),
    baseURL: URL = AppConfig.apiBaseURL,
    marker: any InstallMarkerStore = AppModel.installMarker,
    chatStore: any ChatLogStore = FileChatLogStore.standard
  ) {
    self.chat = ChatKeeper(store: chatStore)
    let session = Session(
      baseURL: baseURL, transport: transport, store: store, marker: marker,
      isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable })
    self.session = session
    self.route = session.route
    #if DEBUG
      if DebugLaunch.followUpReset { followUp.resetDailyLimit() }
    #endif
    session.onRouteChange = { [weak self] route in
      self?.route = route
      if route == .chooseRole {
        self?.invite = nil
        self?.cases = []
        self?.smileBoard = SmileBoard()
        self?.gmail = nil
        self?.photoCache = [:]
        self?.shownPicture = nil
        self?.removePicture()
        // The key is gone (a 401, or this iPhone left the family): her conversation goes with it.
        // Not before the first unlock, when the Keychain only reads as empty.
        if UIApplication.shared.isProtectedDataAvailable { self?.chat.clear() }
        // What was asked after her calls goes too, and the question still waiting on her screen or in
        // Notification Center.
        self?.followUp.forget()
        self?.followUpPrompt = nil
        CallFollowUpNotifier.removeDelivered()
        self?.checkup.forget()
        self?.checkupPrompt = nil
        CheckupNotifier.removeDelivered()
        HeartbeatSender.forget()
      }
      // Joined as the protected member, or no longer: the call watch and the daily prompt follow.
      self?.cameToFront()
    }
  }

  /// 3 minutes, or what a Debug build was launched with (`-mimamori-followup-min-seconds`).
  private static var followUpMinimum: TimeInterval {
    #if DEBUG
      if let seconds = DebugLaunch.followUpMinimum { return seconds }
    #endif
    return CallFollowUp.minimumDuration
  }

  /// An empty file in Application Support: deleted with the app, and checkable while locked.
  nonisolated static let installMarker = FileInstallMarker(
    url: URL.applicationSupportDirectory.appending(path: "mimamori-installed"))

  /// Re-reads the stored key: after the first unlock following a reboot, and whenever the app
  /// comes to the front.
  func refresh() {
    session.refresh()
    // A 401 while locked cleared the key but could not reach her conversation; it goes now.
    if UIApplication.shared.isProtectedDataAvailable { chat.forgetIfLeft(route: route) }
  }

  /// The model the app runs with. Debug builds launched with `-mimamori-stub` use canned answers.
  static func live() -> AppModel {
    #if DEBUG
      if ScreenshotStubTransport.isRequested {
        return AppModel(
          store: InMemoryDeviceKeyStore(ScreenshotStubTransport.joinedAs),
          transport: ScreenshotStubTransport(),
          marker: ScreenshotStubTransport.marker,
          chatStore: ScreenshotStubTransport.chatStore)
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

  // MARK: Deleting everything

  /// "すべて消す" (`DELETE /families/me`). Once the server answers 2xx the key is cleared, and the
  /// route change to role selection clears her conversation and what this run kept (the handler in
  /// `init`). On failure nothing here is deleted and the screen says it was not deleted.
  func deleteEverything() async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await session.deleteEverything()
      problem = nil
    } catch {
      problem = Problem(deleting: error)
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
      await loadSmiles()
      try? await Task.sleep(for: .seconds(60))
    }
  }

  // MARK: Smiles

  /// Quiet on failure, like the cases: the screen keeps what it had.
  func loadSmiles() async {
    guard route != .chooseRole else { return }
    guard let fresh = try? await session.smiles() else { return }
    smileBoard = fresh
  }

  /// The photo of one smile, fetched with the device key. Nil while it cannot be read.
  func photo(for smile: Smile) async -> Data? {
    guard smile.hasPhoto else { return nil }
    if let data = photoCache[smile.id] { return data }
    guard let data = try? await session.smilePhoto(id: smile.id) else { return nil }
    photoCache[smile.id] = data
    return data
  }

  /// The photo the smile camera took. True once the server has it.
  func sendSmile(jpeg: Data, score: Double) async -> Bool {
    await sendSmileBody { try await $0.postSmile(photoJPEG: jpeg, score: score) }
  }

  private func sendSmileBody(_ body: (Session) async throws -> Smile) async -> Bool {
    var sent = false
    await run(joining: false) { [weak self] session in
      let smile = try await body(session)
      sent = true
      self?.smileBoard.smiles.insert(smile, at: 0)
    }
    if sent { await loadSmiles() }
    return sent
  }

  /// The hour (JST) by which her smile is expected; the family is told quietly after it.
  func setSmileDeadline(_ hour: Int) async {
    await run(joining: false) { [weak self] session in
      let saved = try await session.setSmileDeadline(hour: hour)
      self?.smileBoard.deadlineHour = saved
    }
  }

  // MARK: Gmail

  /// Whether her screen offers the Gmail button: no grant yet, or one that runs out within a day.
  var offersGmail: Bool { gmail?.needsGrant(now: now) ?? false }

  /// Quiet on failure. Only her device reads it: the grant is for her inbox (403 for the family).
  func loadGmail() async {
    guard route == .protectedHome else { return }
    gmail = try? await session.gmailConnect()
  }

  /// Opens Google's consent screen in the system sign-in sheet, then reads the grant again.
  func connectGmail() async {
    // A fresh URL on each press: the one read with the screen carries a state that ends after 15 minutes.
    guard let fresh = try? await session.gmailConnect() else {
      problem = .unreachable
      return
    }
    gmail = fresh
    let result = await GmailSignIn.run(url: fresh.url)
    if result == .failed { problem = .unreachable }
    await loadGmail()
  }

  // MARK: Consultation

  /// Reads her conversation once the file can be read (it cannot while the iPhone is locked).
  func loadChat() {
    chat.load()
  }

  /// The send button next to the text field. Never read aloud: she may be among other people.
  func sendTyped(_ text: String) {
    followUp.consultStarted()
    followUpPrompt = nil
    if voice.acceptsText { shownPicture = nil }
    apply(voice.typed(text, at: .now))
  }

  /// The photo button in the field (#221): the image she picked waits on the field, and goes with
  /// her words when she presses send, typed or said (#234). Sent like a shared screenshot
  /// (`ConsultPicture`), never read aloud. Her line and the answer join the conversation; the image is
  /// shown under the answer until her next consultation. Nothing is attached while she is listening or
  /// waiting for an answer, or when it could not be read.
  func attachPicture(_ data: Data) {
    guard voice.acceptsText else { return }
    guard let picture = ConsultPicture(data: data), let image = picture.encoded() else {
      voice.pictureUnreadable()
      return
    }
    guard voice.attachPicture() else { return }
    attachedPicture = picture
    attachedImage = image
  }

  /// The remove button on the attached image.
  func removePicture() {
    voice.removePicture()
    attachedPicture = nil
    attachedImage = nil
  }

  /// The picked image could not be loaded from the picker.
  func pictureUnreadable() {
    voice.pictureUnreadable()
  }

  /// The microphone: starts listening, or stops it.
  func micTapped() {
    if case .listening = voice.phase {
    } else {
      followUp.consultStarted()
      followUpPrompt = nil
      if voice.acceptsText { shownPicture = nil }
    }
    apply(voice.micTapped(at: .now))
  }

  /// The recording field's send button: her words go as they are, as by voice.
  func recordingSendTapped() {
    apply(voice.sendTapped(at: .now))
  }

  /// The recording field's stop button: her words go into the field (`voiceDraft`).
  func recordingStopTapped() {
    apply(voice.stopTapped(at: .now))
  }

  /// The recording field's trash button: nothing is sent.
  func recordingDiscardTapped() {
    apply(voice.discardTapped())
  }

  /// The field took the words from the stop button.
  func takeVoiceDraft() -> String? {
    defer { voiceDraft = nil }
    return voiceDraft
  }

  /// She emptied the field: what she writes next is typed, not said.
  func draftCleared() {
    voice.draftCleared()
  }

  private func listened(_ event: VoiceListener.Event) {
    switch event {
    case .level(let rms): levels.add(rms: rms)
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
        levels.reset()
        #if DEBUG
          // Before `-mimamori-stub-heard` alone, which would send at once.
          if ScreenshotStubTransport.isRequested, ScreenshotStubTransport.listening {
            stubListen()
            continue
          }
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
        #if DEBUG
          if ScreenshotStubTransport.isRequested, ScreenshotStubTransport.listening {
            stubStop()
            continue
          }
        #endif
        listener.stop()
      case .cancelListening:
        #if DEBUG
          stubLevels?.cancel()
        #endif
        listener.cancel()
      case .fillDraft(let text):
        voiceDraft = text
      case .send(let text):
        silenceWatch?.cancel()
        // The turns before this one go with it; then her words join the conversation.
        let history = chat.send(text, at: .now)
        Task { await send(text, history: history) }
      case .sendPicture(let text):
        let attached = (attachedPicture, attachedImage)
        attachedPicture = nil
        attachedImage = nil
        guard let picture = attached.0, let image = attached.1, case .thinking(let line) = voice.phase else {
          voice.sendFailed()
          continue
        }
        silenceWatch?.cancel()
        // Her line only; no earlier turns go with an image, as from the share sheet.
        chat.pictured(line, at: .now)
        shownPicture = ShownPicture(picture: picture, anchor: chat.log.messages.last?.id)
        Task { await send(image, text: text, picture: picture) }
      case .speak(let text):
        speaker.speak([text])
      }
    }
    if case .listening = voice.phase {} else {
      silenceWatch?.cancel()
      levels.reset()
    }
  }

  #if DEBUG
    /// `-mimamori-stub-listening`: listens without the microphone, with the words of
    /// `-mimamori-stub-heard` (if any) as heard so far and dots that move, and no silence stop, so
    /// the recording field can be shot and its buttons pressed on the simulator.
    private func stubListen() {
      apply(voice.listeningStarted(at: .now))
      if let heard = ScreenshotStubTransport.heardText {
        apply(voice.heard(heard, isFinal: false, at: .now))
      }
      stubLevels?.cancel()
      stubLevels = Task { [weak self] in
        var step = 0.0
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(60))
          guard let self, !Task.isCancelled else { return }
          step += 1
          // A voice that rises and falls, from about -40 dB to -6 dB.
          let wave = (sin(step / 3) + sin(step / 1.7)) / 4 + 0.5
          self.levels.add(rms: pow(10, (-40 + 34 * wave) / 20))
        }
      }
    }

    /// The stub's recognizer hands over what it "heard".
    private func stubStop() {
      stubLevels?.cancel()
      guard case .listening(let heard) = voice.phase else { return }
      apply(voice.heard(heard, isFinal: true, at: .now))
    }
  #endif

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

  private func send(_ text: String, history: [ConsultTurn]) async {
    do {
      let answer = try await session.consult(text: text, history: history)
      await answered(answer, reply: answer.reply)
    } catch {
      voice.sendFailed()
    }
  }

  /// The image goes as from the share sheet: the answer asks for the next screenshot when it has a
  /// ring (`ShareConsult.reply`), and the ring goes on the image shown under it.
  private func send(_ image: ConsultImage, text: String, picture: ConsultPicture) async {
    do {
      let answer = try await session.consult(image: image, text: text)
      // A dropped answer leaves the picture as it is: a newer consultation has already replaced it.
      await answered(answer, reply: ShareConsult.reply(for: answer)) {
        self.shownPicture = ShownPicture(
          picture: picture, anchor: self.chat.log.messages.last?.id, circle: picture.circle(for: answer))
      }
    } catch {
      voice.sendFailed()
    }
  }

  /// Puts the answer in her conversation and reads it aloud when it should be. False when it came
  /// after she had started again, and was dropped (VoiceConsult.answered). `kept` runs right after
  /// the answer joins the conversation.
  @discardableResult
  private func answered(_ answer: ConsultAnswer, reply: String, kept: () -> Void = {}) async -> Bool {
    guard case .thinking = voice.phase else { return false }
    chat.answered(reply, at: .now)
    kept()
    // 「読み上げ」 in Settings > みまもり, off unless turned on (#115). Read for each answer: the
    // Settings app is another process and sends no notice of the change.
    let readAloud = ReadAloudSettings(reading: { UserDefaults.standard.object(forKey: $0) })
    apply(voice.answered(answer, readsAloud: readAloud.isOn))
    // The case shows up: "家族に伝えました", or "家族に届いていません" while no family device took it.
    if answer.handoff { await loadCases() }
    return true
  }

  // MARK: Call follow-up

  /// Each time the app comes to the front, at launch, and when the route changes. Only the protected
  /// member's iPhone watches calls and gets the daily prompt; on any other route both stop.
  ///
  /// Settings > みまもり is read here too. The Settings app is another process, and Apple's page on
  /// `UserDefaults.didChangeNotification` says "If a different process changes your app's settings,
  /// the system doesn't generate this notification"; a suspended app could not act on it anyway. A
  /// new value takes effect the next time the app comes to the front.
  func cameToFront() {
    if route == .protectedHome { callWatcher.start() } else { callWatcher.stop() }
    scheduleDailyCheckIns()
    Task { await runCheckups() }
  }

  /// The app's settings screen (`SettingsView`, #222) wrote a new value. The daily prompts are
  /// rebuilt now, through the same path as coming to the front; 「読み上げ」 needs nothing, since it is
  /// read for each answer.
  func settingsChanged() {
    scheduleDailyCheckIns()
  }

  // MARK: Checkups (task 17, #19)

  /// The checks and the heartbeat, on the protected member's iPhone only: each time the app comes to
  /// the front, and from the background refresh (`CheckupBackground`).
  func runCheckups() async {
    guard route == .protectedHome else {
      CheckupBackground.cancel()
      return
    }
    CheckupBackground.schedule()
    let available = CheckupNotifier.availableBytes()
    if case .notify(let text) = checkup.storageChecked(availableBytes: available, at: checkupNow) {
      await CheckupNotifier.post(text)
    }
    refreshCheckup(availableBytes: available)
    await sendHeartbeat()
  }

  /// Now, or in a Debug build launched with `-mimamori-now-hour <h>`, today at that hour.
  private var checkupNow: Date {
    #if DEBUG
      if let hour = DebugLaunch.nowHour {
        let now = Date.now
        return Calendar.current.date(bySettingHour: hour, minute: Calendar.current.component(.minute, from: now), second: 0, of: now) ?? now
      }
    #endif
    return .now
  }

  /// When the screen appears or the app comes to the front.
  func refreshCheckup(availableBytes: Int64? = CheckupNotifier.availableBytes()) {
    checkupPrompt = checkup.storagePromptToShow(availableBytes: availableBytes, at: checkupNow)
  }

  /// "あとで": nothing about free space for 24 hours.
  func checkupLater() {
    checkup.later(at: checkupNow)
    checkupPrompt = nil
  }

  /// "空ける", or a tap on the notification: the prompt closes and the guide to Settings >
  /// iPhoneストレージ is the first answer in her chat. Kept on this iPhone only.
  func startStorageGuide() {
    guard route == .protectedHome else { return }
    chat.guide(checkup.startStorageGuide(), at: .now)
    checkupPrompt = nil
    CheckupNotifier.removeDelivered()
  }

  private func sendHeartbeat() async {
    let previous = heartbeatWork
    let work = Task { [weak self] in
      await previous?.value
      guard let self, route == .protectedHome else { return }
      let report = await HeartbeatSender.report()
      var gate = HeartbeatSender.gate()
      guard gate.shouldSend(report, at: .now) else { return }
      // Quiet on failure: the next foreground or background refresh tries again.
      guard (try? await session.heartbeat(report)) != nil else { return }
      gate.sent(report, at: .now)
      HeartbeatSender.save(gate)
    }
    heartbeatWork = work
    await work.value
  }

  /// A call ended while the app was in front (`CallEndWatcher`, #99).
  func callEnded(_ call: EndedCall) async {
    switch followUp.callEnded(call) {
    case .notifyNow:
      await CallFollowUpNotifier.post()
      refreshFollowUp()
      // She was asked about a call today: today's daily prompt goes.
      scheduleDailyCheckIns()
    case .askOnNextOpen:
      refreshFollowUp()
      scheduleDailyCheckIns()
    case .nothing:
      break
    }
  }

  /// Replaces the pending daily prompts with the ones for the next days. Nothing on a family
  /// member's iPhone, or before joining.
  private func scheduleDailyCheckIns() {
    let previous = checkInWork
    checkInWork = Task { [weak self] in
      await previous?.value
      guard let self else { return }
      // Read now, after the one before finished, so the newest settings and route win.
      let settings = DailyCheckInNotifier.settings
      let protected = route == .protectedHome
      await DailyCheckInNotifier.replace(with: protected ? followUp.dailyCheckIns(settings, now: .now) : [])
      #if DEBUG
        if protected, settings.isOn, !postedDebugCheckIn, let seconds = DebugLaunch.checkInAfter {
          postedDebugCheckIn = true
          await DailyCheckInNotifier.postSoon(after: seconds)
        }
      #endif
    }
  }

  /// When the screen appears or the app comes to the front.
  func refreshFollowUp() {
    followUpPrompt = followUp.promptToShow(at: .now)
  }

  /// "わかった": the prompt closes and nothing else happens.
  func followUpAcknowledged() {
    followUp.acknowledged()
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
    #if DEBUG
      // The stub has no APNs, and the permission sheet would cover the screenshots.
      if ScreenshotStubTransport.isRequested { return }
    #endif
    let granted =
      (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])) ?? false
    if granted { UIApplication.shared.registerForRemoteNotifications() }
    // Requests added before she allowed notifications may not have been kept.
    guard granted else { return }
    #if DEBUG
      // The Debug prompt may have been added while the permission sheet was still up; add it again
      // (same identifier, so it replaces rather than doubles).
      postedDebugCheckIn = false
    #endif
    scheduleDailyCheckIns()
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

/// The screenshot under her line, then under the answer, with the ring where to press.
struct ShownPicture {
  let picture: ConsultPicture
  /// The message it shows under: her line while waiting, the answer once it came.
  let anchor: UUID?
  var circle: PixelPoint? = nil
}
