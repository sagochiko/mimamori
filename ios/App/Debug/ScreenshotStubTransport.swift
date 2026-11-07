#if DEBUG
  import Foundation
  import MimamoriCore

  /// Debug builds only. Launched with `-mimamori-stub`, the app answers its own API calls with
  /// made-up data and keeps the device key in memory, so every screen can be shown on the simulator
  /// before the Workers host exists. Release builds never contain this file's code.
  struct ScreenshotStubTransport: HTTPTransport {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub") }
    /// With `-mimamori-stub-heard <text>`, pressing the microphone "hears" that text at once, since the
    /// simulator has no on-device Japanese recognition. The answer comes from the stub below.
    static var heardText: String? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: "-mimamori-stub-heard"), i + 1 < args.count else { return nil }
      return args[i + 1]
    }
    /// With `-mimamori-stub-joined protected` (or `family`), the app starts on that home screen
    /// instead of role selection, so a screen can be shot without tapping through joining.
    static var joinedAs: Credentials? {
      guard let role = value(after: "-mimamori-stub-joined").flatMap(Role.init(rawValue:)) else { return nil }
      // The stub's key lives in memory; a missing marker would clear it on the first refresh.
      _ = marker.mark()
      return Credentials(deviceKey: "dk-stub", memberId: "m-stub", familyId: "f-stub", role: role)
    }
    /// With `-mimamori-stub-draft <text>`, the text field starts with that text, ready to send.
    static var draftText: String? { value(after: "-mimamori-stub-draft") }
    /// With `-mimamori-stub-notices-open`, the family notices at the top start opened.
    static var noticesOpen: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-notices-open") }
    /// With `-mimamori-stub-camera-open`, the home screen opens the smile camera at once.
    static var cameraOpen: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-camera-open") }
    static var gmailButton: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-gmail") }
    /// With `-mimamori-stub-photo-open`, the home screen opens the photo button's picker at once (#221).
    static var photoOpen: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-photo-open") }
    /// With `-mimamori-stub-photo-pick`, the home screen sends `StubPicture` at once, as if she had picked
    /// it with the photo button: the picker runs outside the app and a test cannot reach into it.
    /// With `-mimamori-stub-draft`, its words go with the image.
    static var photoPick: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-photo-pick") }
    /// With `-mimamori-stub-wipe-open`, the check before "すべて消す" ("消す" or "やめる") opens at once.
    static var wipeOpen: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-wipe-open") }
    /// With `-mimamori-stub-wipe-fail`, "すべて消す" answers 502 `cleanup_failed`, as when Google or
    /// Anthropic refused, so the failure can be shot.
    static var wipeFails: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-wipe-fail") }
    /// With `-mimamori-stub-camera-hold`, the stand-in camera never "sees" the smile, so the camera
    /// screen itself can be shot.
    static var cameraHold: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-camera-hold") }
    /// `-mimamori-stub-settings-open`: her settings screen (#222) is open at launch.
    static var settingsOpen: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub-settings-open") }
    /// The stub keeps the key in memory, so the real marker file is left alone.
    static let marker = FileInstallMarker(url: URL.temporaryDirectory.appending(path: "mimamori-stub-installed"))
    /// The conversation stays in memory too, so her real one is left alone. With
    /// `-mimamori-stub-chat police` it starts with the fake-police question asked a few minutes ago.
    static let chatStore = StubChatStore(seed: value(after: "-mimamori-stub-chat"))

    private static func value(after flag: String) -> String? {
      let args = ProcessInfo.processInfo.arguments
      guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
      return args[i + 1]
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      try await Task.sleep(for: .milliseconds(300))
      let path = request.url?.path ?? ""
      if request.httpMethod == "GET", path.hasPrefix("/smiles/"), path.hasSuffix("/photo") {
        return Self.photo(for: request, path: path)
      }
      let (status, body): (Int, String) =
        switch (request.httpMethod ?? "", path) {
        case ("POST", "/families"):
          (201, Self.joinAnswer(role: "family"))
        case ("POST", "/invites"):
          (201, #"{"code":"482913","expiresAt":"\#(Date.now.addingTimeInterval(86_400).ISO8601Format())"}"#)
        case ("POST", let p) where p.hasPrefix("/invites/") && p.hasSuffix("/join"):
          p.contains("/000000/")
            ? (404, #"{"error":"not_found"}"#)
            : (201, Self.joinAnswer(role: Self.role(in: request)))
        case ("PUT", "/members/me/apns"):
          (204, "")
        case ("POST", "/consult") where Self.body(of: request)["image"] != nil:
          (200, Self.pictureAnswer(to: Self.body(of: request)))
        case ("POST", "/consult"):
          (200, Self.consultAnswer(to: Self.field("text", in: request) ?? "", hasHistory: Self.hasHistory(request)))
        case ("GET", "/cases"):
          (200, StubCases.shared.list())
        case ("POST", let p) where p.hasPrefix("/cases/"):
          StubCases.shared.act(path: p)
        case ("GET", "/smiles"):
          (200, StubSmiles.shared.list())
        case ("POST", "/smiles"):
          StubSmiles.shared.add(Self.body(of: request))
        case ("GET", "/gmail/connect"):
          // The button shows only with -mimamori-stub-gmail, so other screenshots of her screen stay as they were.
          Self.gmailButton
            ? (200, #"{"url":"https://accounts.google.com/o/oauth2/v2/auth","grantedAt":null}"#)
            : (503, #"{"error":"gmail_not_configured"}"#)
        case ("DELETE", "/families/me"):
          Self.wipeFails ? (502, #"{"error":"cleanup_failed","pending":["gmail"]}"#) : (204, "")
        case ("PUT", "/families/me/smile-deadline"):
          StubSmiles.shared.setHour(Self.body(of: request)["hour"] as? Int)
        default:
          (404, "{}")
        }
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      return (Data(body.utf8), response)
    }

    private static func body(of request: URLRequest) -> [String: Any] {
      guard let data = request.httpBody,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return [:] }
      return json
    }

    /// The drawn face (`SmilePlaceholder`), or the photo the stand-in camera "took".
    private static func photo(for request: URLRequest, path: String) -> (Data, HTTPURLResponse) {
      let id = path.split(separator: "/").dropFirst().first.map(String.init) ?? ""
      let data = StubSmiles.shared.photo(id: id)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: data == nil ? 404 : 200, httpVersion: nil,
        headerFields: ["Content-Type": "image/jpeg"])!
      return (data ?? Data(), response)
    }

    private static func hasHistory(_ request: URLRequest) -> Bool {
      guard let data = request.httpBody,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let history = json["history"] as? [Any]
      else { return false }
      return !history.isEmpty
    }

    private static func field(_ key: String, in request: URLRequest) -> String? {
      guard let data = request.httpBody,
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return nil }
      return json[key] as? String
    }

    fileprivate static func json(_ value: Any) -> String {
      String(decoding: try! JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    /// The fake-police answer for anything about the police, a follow-up answer for "どういうこと"
    /// when earlier turns came along (the server reads them, #73), otherwise the storage guidance.
    private static func consultAnswer(to text: String, hasHistory: Bool) -> String {
      let police = "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて"
      let followUp = "警察を名乗る相手が、口座のことでビデオ通話や送金を求めるのは、詐欺で使われる説明と一致しています。電話を切って、家族に確かめて"
      let storage = "設定の「一般」から「iPhone ストレージ」を開くと、空きを作れます。広告の掃除アプリは入れなくていいよ"
      let (reply, handoff): (String, Bool) =
        if text.contains("警察") { (police, true) }
        else if hasHistory && text.contains("どういう") { (followUp, false) }
        else { (storage, false) }
      return json([
        "reply": reply, "speak": reply.replacingOccurrences(of: "「", with: "").replacingOccurrences(of: "」", with: ""),
        "handoff": handoff,
      ])
    }

    /// For an image (the share sheet or the chat's photo button): a ring in the middle of what was
    /// sent, so the circle can be shot on the simulator.
    private static func pictureAnswer(to body: [String: Any]) -> String {
      let image = body["image"] as? [String: Any] ?? [:]
      let width = image["width"] as? Int ?? 0
      let height = image["height"] as? Int ?? 0
      let reply = "丸のところを押して"
      return json([
        "reply": reply, "speak": reply, "handoff": false,
        "tap": ["x": Double(width) / 2, "y": Double(height) / 2],
      ])
    }

    private static func role(in request: URLRequest) -> String { field("role", in: request) ?? "protected" }

    /// Same shape as the task 2 server: `{familyId, memberId, deviceKey, familyToken, role}`.
    private static func joinAnswer(role: String) -> String {
      let answer = [
        "familyId": "f-stub", "memberId": "m-stub", "deviceKey": "dk-stub",
        "familyToken": "00000000000000000000000000000000", "role": role,
      ]
      let data = try! JSONSerialization.data(withJSONObject: answer)
      return String(decoding: data, as: UTF8.self)
    }
  }

  /// Made-up smiles for the screenshots: 母 this morning, 妹's smile, and 作者's reply, all with drawn
  /// faces. `-mimamori-stub-smiles none` starts with none, so the morning without her smile can be shot.
  final class StubSmiles: @unchecked Sendable {
    static let shared = StubSmiles()
    private let lock = NSLock()
    private var smiles: [[String: Any]] = []
    private var photos: [String: Data] = [:]
    private var hour = SmileBoard.defaultDeadlineHour

    private init() {
      let args = ProcessInfo.processInfo.arguments
      if let i = args.firstIndex(of: "-mimamori-stub-smiles"), i + 1 < args.count, args[i + 1] == "none" { return }
      let now = Date.now
      func at(_ minutesAgo: Double) -> String { now.addingTimeInterval(-minutesAgo * 60).ISO8601Format() }
      // Her smile is placed earlier today, but never before midnight, so it counts as today's.
      let sinceMidnight = now.timeIntervalSince(Calendar.current.startOfDay(for: now)) / 60
      let hers = min(45, max(1, sinceMidnight - 1))
      smiles = [
        Self.row("s-owner", "m-owner", "作者", "family", photo: true, note: nil, at: at(hers * 0.3)),
        Self.row("s-sister", "m-sister", "妹", "family", photo: true, note: nil, at: at(hers * 0.6)),
        Self.row("s-mother", "m-mother", "母", "protected", photo: true, note: nil, at: at(hers)),
      ]
      photos = [
        "s-owner": SmilePlaceholder.jpeg(variant: 3), "s-sister": SmilePlaceholder.jpeg(variant: 1),
        "s-mother": SmilePlaceholder.jpeg(variant: 2),
      ]
    }

    private static func row(
      _ id: String, _ member: String, _ name: String, _ role: String, photo: Bool, note: String?, at: String
    ) -> [String: Any] {
      [
        "id": id, "memberId": member, "displayName": name, "role": role, "score": photo ? 0.8 : NSNull(),
        "note": note ?? NSNull(), "hasPhoto": photo, "createdAt": at,
      ]
    }

    func list() -> String {
      lock.withLock { ScreenshotStubTransport.json(["smiles": smiles, "deadlineHour": hour]) }
    }

    func photo(id: String) -> Data? { lock.withLock { photos[id] } }

    /// As the stub's own member ("m-stub"), named after the role it joined as.
    func add(_ body: [String: Any]) -> (Int, String) {
      let photo = (body["photo"] as? String).flatMap { Data(base64Encoded: $0) }
      // Set words only, as on the server: an id or the words themselves.
      let sent = body["note"] as? String
      let note = SmileNote.allCases.first { $0.rawValue == sent || $0.text == sent }?.text
      if sent != nil && note == nil { return (400, #"{"error":"note_not_allowed"}"#) }
      guard photo != nil || note != nil else { return (400, #"{"error":"smile_empty"}"#) }
      let role = ScreenshotStubTransport.joinedAs?.role ?? .family
      let id = "s-\(UUID().uuidString.prefix(8))"
      let row = Self.row(
        id, "m-stub", role == .protected ? "母" : "作者", role.rawValue, photo: photo != nil, note: note,
        at: Date.now.ISO8601Format())
      return lock.withLock {
        smiles.insert(row, at: 0)
        if let photo { photos[id] = photo }
        return (201, ScreenshotStubTransport.json(row))
      }
    }

    func setHour(_ value: Int?) -> (Int, String) {
      guard let value, SmileBoard.deadlineHours.contains(value) else { return (400, #"{"error":"hour_invalid"}"#) }
      return lock.withLock {
        hour = value
        return (200, ScreenshotStubTransport.json(["deadlineHour": value]))
      }
    }
  }

  /// Her conversation for the screenshots, in memory only.
  final class StubChatStore: ChatLogStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    /// `police` is the fake-police question and its answer; `followup` adds "それってどういうこと?" and
    /// its answer after them; `days` puts a question and its answer of yesterday at 14:55 before them,
    /// so the date rows show (#113).
    init(seed: String?) {
      guard ["police", "followup", "days"].contains(seed) else { return }
      var log = ChatLog()
      let now = Date.now
      if seed == "days" {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let asked = calendar.date(bySettingHour: 14, minute: 55, second: 0, of: yesterday) ?? yesterday
        log.append(.protected, "写真を消さずに空きを増やすには?", at: asked)
        log.append(.ai, "設定の「一般」から「iPhoneストレージ」を開くと、大きいアプリが上から並びます", at: asked.addingTimeInterval(40))
      }
      log.append(.protected, "警察から電話があって、口座が犯罪に使われてるって。ほかの人には言わないでって", at: now.addingTimeInterval(-180))
      log.append(.ai, "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて", at: now.addingTimeInterval(-175))
      if seed == "followup" {
        log.append(.protected, "それってどういうこと?", at: now.addingTimeInterval(-120))
        log.append(.ai, "警察を名乗る相手が、口座のことでビデオ通話や送金を求めるのは、詐欺で使われる説明と一致しています。電話を切って、家族に確かめて", at: now.addingTimeInterval(-115))
      }
      data = try? log.encoded()
    }

    func read() throws -> Data? { lock.withLock { data } }
    func write(_ data: Data) throws { lock.withLock { self.data = data } }
    func remove() throws { lock.withLock { data = nil } }
  }

  /// Made-up cases for the screenshots: one just sent to the family, one that did not reach any family
  /// device yet (#60), one the sister resolved, and one not resolved for 40 minutes. "解決" resolves
  /// one as 作者.
  final class StubCases: @unchecked Sendable {
    static let shared = StubCases()
    private let lock = NSLock()
    private var cases: [[String: Any]]

    private init() {
      let now = Date.now
      func at(_ minutesAgo: Double) -> String { now.addingTimeInterval(-minutesAgo * 60).ISO8601Format() }
      func alert(_ level: Int, _ source: String, _ summary: String, _ reason: String) -> [String: Any] {
        ["level": level, "source": source, "summary": summary, "reasons": [reason]]
      }
      cases = [
        [
          "id": "c-police", "alertId": "a-1", "state": "notified", "notifiedAt": at(3), "familyNotifiedAt": at(3),
          "alert": alert(1, "consult", "警察を名乗る電話の相談", "口座が犯罪に使われたという話がある"),
          "aiReply": "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて",
        ],
        [
          // An SMS whose research in the background came back (task 11); the evidence is read by VoiceOver.
          "id": "c-sms", "alertId": "a-5", "state": "notified", "notifiedAt": at(6), "familyNotifiedAt": at(6),
          "alert": alert(1, "sms", "SMS 宅配便を名乗る example.top", "送り主のドメインが公式と違う")
            .merging(["evidence": [[
              "text": "日本郵政グループの注意喚起",
              "url": "https://www.post.japanpost.jp/notification/",
            ]]]) { $1 },
        ],
        [
          "id": "c-unreached", "alertId": "a-4", "state": "notified", "notifiedAt": at(2), "familyNotifiedAt": NSNull(),
          "alert": alert(2, "consult", "スマホの相談", "AI が答えきれなかった相談"),
          "aiReply": "うまく答えられませんでした。家族に届いていません。急ぐなら電話して",
        ],
        [
          "id": "c-sister", "alertId": "a-2", "state": "resolved", "notifiedAt": at(20), "resolvedAt": at(12),
          "familyNotifiedAt": at(20),
          "resolvedBy": ["memberId": "m-sister", "displayName": "妹"],
          "alert": alert(1, "sms", "SMS 暗証番号やパスワードを求めている bank-check.example", "暗証番号やパスワードを求めている"),
        ],
        [
          "id": "c-old", "alertId": "a-3", "state": "notified", "notifiedAt": at(40), "renotifiedAt": at(5),
          "familyNotifiedAt": at(40),
          "alert": alert(2, "sms", "SMS 宅配の不在の知らせをかたっている parcel-notice.example", "宅配の不在の知らせをかたっている"),
        ],
      ]
    }

    func list() -> String {
      lock.withLock { ScreenshotStubTransport.json(["cases": cases]) }
    }

    /// `/cases/{id}/resolve`. The stub's member is "m-stub", shown as 作者. Other verbs are gone (404).
    func act(path: String) -> (Int, String) {
      let parts = path.split(separator: "/").map(String.init)
      guard parts.count == 3, parts[2] == "resolve" else { return (404, #"{"error":"not_found"}"#) }
      return lock.withLock {
        guard let i = cases.firstIndex(where: { $0["id"] as? String == parts[1] }) else { return (404, "{}") }
        if cases[i]["state"] as? String != "resolved" {
          cases[i]["state"] = "resolved"
          cases[i]["resolvedAt"] = Date.now.ISO8601Format()
          cases[i]["resolvedBy"] = ["memberId": "m-stub", "displayName": "作者"]
        }
        return (200, ScreenshotStubTransport.json(cases[i]))
      }
    }
  }
#endif
