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

  @ObservationIgnored private let session: Session
  @ObservationIgnored private let announcer = ReplyAnnouncer(store: UserDefaultsSpokenStore())
  @ObservationIgnored private lazy var speaker = ReplySpeaker()

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
    let me = session.memberId
    return cases.map { FamilyCard($0, me: me) }
  }

  var protectedNotices: [ProtectedNotice] {
    ProtectedNotice.notices(from: cases, now: now)
  }

  /// Reloads the cases. Quiet on failure: the screen keeps what it had and the next refresh tries again.
  /// On the protected person's phone, replies not read aloud yet are spoken.
  func loadCases() async {
    guard route != .chooseRole else { return }
    now = .now
    guard let fresh = try? await session.cases() else { return }
    cases = fresh
    if route == .protectedHome {
      speaker.speak(announcer.toSpeak(protectedNotices))
    }
  }

  /// Every minute while the screen is showing. Cancelled with the view's task.
  func keepCasesFresh() async {
    while !Task.isCancelled {
      await loadCases()
      try? await Task.sleep(for: .seconds(60))
    }
  }

  /// Reads a reply again when the protected person taps it.
  func speakAgain(_ reply: ProtectedNotice.Reply) {
    speaker.stop()
    speaker.speak(["\(reply.from)。\(reply.body)"])
  }

  func accept(_ item: Case) async {
    await run(joining: false) { [weak self] session in
      let updated = try await session.accept(caseId: item.id)
      self?.replace(updated)
    }
    // Someone else may have been first; show who.
    await loadCases()
  }

  /// Nil when the reply was sent, otherwise why not. The composer sheet shows the failure itself
  /// (an alert from the root view would land under the sheet), so `problem` is left alone.
  func relay(_ item: Case, text: String) async -> Problem? {
    isBusy = true
    defer { isBusy = false }
    do {
      try await session.relay(caseId: item.id, body: text)
    } catch {
      return Problem(error, joining: false)
    }
    await loadCases()
    return nil
  }

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
