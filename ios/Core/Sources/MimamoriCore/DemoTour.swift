import Foundation

// The judges' tour on one iPhone (#100, task 6 in docs/plan.md, "検知" in docs/design.md). The server
// cannot tell whose iPhone an SMS query comes from, so the judges' build sends them to `demo`, which
// tells no family and answers with the card the family would get. The tour starts with the main line,
// the call follow-up and the fake-police consultation, shows her screen and the family card side by
// side, lets the judge press "解決" or let 30 minutes pass with no one, and then try an SMS.
//
// Nothing in the tour talks to a family. The consultation is played from the server's fixed lines for
// the fake-police script instead of calling `POST /consult`, which needs a protected member of a real
// family; only the SMS goes to the server, to `/sms/demo`, without a device key.

/// Whether this build is the judges' one. The switch is the SMS token itself: the mother's build sets
/// her family's token (ios/Config/Mother.xcconfig), so it can never show the tour. Until #133 is done
/// the mother still gets the `demo` build, so the tour shows on her role selection too (it sends
/// nothing to anyone).
public enum DemoMode {
  public static let smsFamilyToken = "demo"

  public static func isOn(smsFamilyToken token: String?) -> Bool {
    token == smsFamilyToken
  }
}

/// A notification the family's iPhones would show, as the server's `notify` sends it (server/src/cases.ts).
public struct DemoPush: Equatable, Sendable {
  public let title: String
  public let body: String

  public init(title: String, body: String) {
    self.title = title
    self.body = body
  }
}

public struct DemoTour: Equatable, Sendable {
  public enum Step: Equatable, Sendable {
    /// `CallFollowUp.prompt` waits on her screen.
    case asked
    /// She pressed "わかった" and closed it: nothing goes to anyone.
    case acknowledged
    /// She told the AI about the call; the family has the card.
    case consulted
    /// A family member pressed "解決".
    case resolved
    /// 30 minutes passed with no one pressing "解決".
    case unanswered
  }

  /// A fake-police call as she might tell it. Fictional, written for the tour.
  public static let herWords = "警察から電話があって、口座が犯罪に使われてるって。ほかの人には言わないでって"
  /// server/src/consult-judge.ts MATCH_BASIS + POLICE_ACTION, the fixed answer for the fake-police script.
  public static let answer = "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて"
  /// server/src/consult-judge.ts POLICE_TOPIC, the family's one line.
  public static let topic = "警察を名乗る電話の相談"
  /// The reasons the server gives for `herWords` (server/src/rules/phrases.ts POLICE_SCRIPT), as the
  /// family's card reads them aloud. server/test/demo-tour.test.ts runs her words through the server's
  /// judgment and compares, so this cannot drift.
  public static let reasons = ["口座が犯罪に使われたという話がある", "ほかの人に話さないよう言われている"]
  /// server/src/cases.ts NOT_RESOLVED_YET, the title of the family's second notice.
  public static let notResolvedYet = "まだ解決していません"

  public private(set) var step: Step = .asked
  public private(set) var messages: [ChatMessage] = []
  private var consultedAt: Date?
  private var resolvedAt: Date?
  /// Set once the tour skipped the 30 minutes; it stays when "解決" is pressed after that.
  private var waited = false

  public init() {}

  /// The follow-up on her screen, while it waits for an answer.
  public var prompt: String? { step == .asked ? CallFollowUp.prompt : nil }

  /// "解決" or "30分" can be chosen.
  public var canChoose: Bool { step == .consulted }

  /// The tour reached one of its ends; the SMS and "最初から" come next.
  public var isFinished: Bool { step == .acknowledged || step == .resolved || step == .unanswered }

  public mutating func acknowledge() {
    guard step == .asked else { return }
    step = .acknowledged
  }

  public mutating func consult(at now: Date) {
    guard step == .asked else { return }
    step = .consulted
    consultedAt = now
    messages = [
      ChatMessage(id: UUID(), role: .protected, text: Self.herWords, at: now),
      ChatMessage(id: UUID(), role: .ai, text: Self.answer, at: now),
    ]
  }

  /// "解決" on the family card. Also after the 30 minutes, as on a real card.
  public mutating func resolve(at now: Date) {
    guard step == .consulted || step == .unanswered else { return }
    step = .resolved
    resolvedAt = clock(now: now)
  }

  /// The judge does not wait 30 minutes: the tour's clock jumps past the server's watch.
  public mutating func waitHalfHour() {
    guard step == .consulted else { return }
    step = .unanswered
    waited = true
  }

  public mutating func restart() {
    self = DemoTour()
  }

  /// The time on the tour's clock: 30 minutes and a second ahead once the half hour was skipped.
  public func clock(now: Date) -> Date {
    waited ? now.addingTimeInterval(ProtectedNotice.unansweredAfter + 1) : now
  }

  private var renotifiedAt: Date? {
    guard waited, let consultedAt else { return nil }
    return consultedAt.addingTimeInterval(ProtectedNotice.unansweredAfter)
  }

  /// The case the family's screen shows, as `GET /cases` would return it.
  public var familyCase: Case? {
    guard let consultedAt, step != .asked, step != .acknowledged else { return nil }
    let resolved = step == .resolved
    return Case(
      id: "demo-police", alertId: nil, state: resolved ? .resolved : .notified,
      notifiedAt: consultedAt,
      resolvedAt: resolved ? resolvedAt : nil,
      resolvedBy: resolved ? CaseMember(memberId: "demo-family", displayName: "家族") : nil,
      renotifiedAt: renotifiedAt,
      alert: CaseAlert(
        level: .doNotOpen, source: .consult, summary: Self.topic, reasons: Self.reasons),
      aiReply: Self.answer, familyNotifiedAt: consultedAt)
  }

  /// The strip at the top of her screen, through the same rules as her real screen.
  public func protectedNotices(now: Date) -> [ProtectedNotice] {
    ProtectedNotice.notices(from: familyCase.map { [$0] } ?? [], now: clock(now: now))
  }

  /// The last notification the family's iPhones got for the case. "解決" by one of them sends the
  /// others "(名前)が解決", but the card the judge sees is the one who pressed it.
  public var familyPush: DemoPush? {
    switch step {
    case .asked, .acknowledged: nil
    case .consulted, .resolved:
      waited
        ? DemoPush(title: Self.notResolvedYet, body: Self.topic)
        : DemoPush(title: Level.doNotOpen.familyBadge, body: Self.topic)
    case .unanswered: DemoPush(title: Self.notResolvedYet, body: Self.topic)
    }
  }
}

/// What `/sms/demo` answered: where Apple would put the SMS, and the card the family would get.
public struct DemoSMSResult: Equatable, Sendable {
  public let verdict: SMSFilterVerdict
  /// Nil when the rules would not tell the family (no level, or level 3). Never read as "safe".
  public let card: Case?
}

/// Trying an SMS in the tour: the same request Apple makes for the Message Filter extension, sent to
/// `demo`, so no family is told (server/src/sms.ts). The text is data; the server reads it as such.
public enum DemoSMS {
  public static func request(baseURL: URL, text: String) throws -> URLRequest {
    var request = URLRequest(
      url: baseURL.appending(path: "sms").appending(path: DemoMode.smsFamilyToken))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = ["_version": 1, "query": ["message": ["text": text]]]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  /// Nil when the server did not answer in its shape.
  public static func result(statusCode: Int, data: Data, at now: Date) -> DemoSMSResult? {
    guard (200..<300).contains(statusCode),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      object["action"] is String
    else { return nil }
    let verdict = SMSFilterReply.verdict(statusCode: statusCode, data: data)
    return DemoSMSResult(verdict: verdict, card: card(object["card"], at: now))
  }

  public static func check(
    text: String, baseURL: URL, transport: any HTTPTransport, at now: Date
  ) async throws -> DemoSMSResult {
    let (data, response) = try await transport.send(try request(baseURL: baseURL, text: text))
    guard let result = result(statusCode: response.statusCode, data: data, at: now) else {
      throw URLError(.badServerResponse)
    }
    return result
  }

  private static func card(_ value: Any?, at now: Date) -> Case? {
    guard let card = value as? [String: Any],
      let raw = card["level"] as? Int, let level = Level(rawValue: raw), level != .lowConcern,
      let summary = card["summary"] as? String
    else { return nil }
    let reasons = (card["reasons"] as? [String]) ?? []
    return Case(
      id: "demo-sms", alertId: nil, state: .notified, notifiedAt: now,
      alert: CaseAlert(level: level, source: .sms, summary: summary, reasons: reasons),
      familyNotifiedAt: now)
  }
}

extension Case {
  /// The SMS card after "解決" in the tour: what `POST /cases/{id}/resolve` would answer.
  public func resolvedInDemo(at now: Date) -> Case {
    guard state == .notified else { return self }
    return Case(
      id: id, alertId: alertId, state: .resolved, notifiedAt: notifiedAt, resolvedAt: now,
      resolvedBy: CaseMember(memberId: "demo-family", displayName: "家族"),
      renotifiedAt: renotifiedAt,
      alert: alert, aiReply: aiReply, familyNotifiedAt: familyNotifiedAt)
  }
}
