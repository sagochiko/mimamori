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
    /// The stub keeps the key in memory, so the real marker file is left alone.
    static let marker = FileInstallMarker(url: URL.temporaryDirectory.appending(path: "mimamori-stub-installed"))

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      try await Task.sleep(for: .milliseconds(300))
      let path = request.url?.path ?? ""
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
        case ("POST", "/consult"):
          (200, Self.consultAnswer(to: Self.field("text", in: request) ?? ""))
        case ("GET", "/cases"):
          (200, StubCases.shared.list())
        case ("POST", let p) where p.hasPrefix("/cases/"):
          StubCases.shared.act(path: p)
        default:
          (404, "{}")
        }
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      return (Data(body.utf8), response)
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

    /// The fake-police answer for anything about the police, otherwise the storage guidance.
    private static func consultAnswer(to text: String) -> String {
      let police = "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて"
      let storage = "設定の「一般」から「iPhone ストレージ」を開くと、空きを作れます。広告の掃除アプリは入れなくていいよ"
      let reply = text.contains("警察") ? police : storage
      return json([
        "reply": reply, "speak": reply.replacingOccurrences(of: "「", with: "").replacingOccurrences(of: "」", with: ""),
        "handoff": text.contains("警察"),
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

  /// Made-up cases for the screenshots: one just sent to the family, one the sister resolved, and one
  /// not resolved for 40 minutes. "解決" resolves one as 作者.
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
          "id": "c-police", "alertId": "a-1", "state": "notified", "notifiedAt": at(3),
          "alert": alert(1, "consult", "警察を名乗る電話の相談", "口座が犯罪に使われたという話がある"),
          "aiReply": "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて",
        ],
        [
          "id": "c-sister", "alertId": "a-2", "state": "resolved", "notifiedAt": at(20), "resolvedAt": at(12),
          "resolvedBy": ["memberId": "m-sister", "displayName": "妹"],
          "alert": alert(1, "sms", "SMS 暗証番号やパスワードを求めている bank-check.example", "暗証番号やパスワードを求めている"),
        ],
        [
          "id": "c-old", "alertId": "a-3", "state": "notified", "notifiedAt": at(40), "renotifiedAt": at(5),
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
