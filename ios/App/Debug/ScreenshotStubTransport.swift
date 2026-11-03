#if DEBUG
  import Foundation
  import MimamoriCore

  /// Debug builds only. Launched with `-mimamori-stub`, the app answers its own API calls with
  /// made-up data and keeps the device key in memory, so every screen can be shown on the simulator
  /// before the Workers host exists. Release builds never contain this file's code.
  struct ScreenshotStubTransport: HTTPTransport {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-mimamori-stub") }
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
        case ("GET", "/cases"):
          (200, StubCases.shared.list())
        case ("POST", let p) where p.hasPrefix("/cases/"):
          StubCases.shared.act(path: p, body: Self.field("body", in: request))
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

  /// Made-up cases for the screenshots: one just sent to the family, one the sister took and
  /// answered, and one nobody took for 40 minutes. Accepting, replying, and resolving change them.
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
          "alert": alert(1, "call", "警察を名乗る電話の相談", "口座が犯罪に使われていると言い、送金を求めた"),
          "aiReply": "詐欺で使われる説明と一致しています。送金せず、いったん電話を切って家族に確かめて",
          "relays": [],
        ],
        [
          "id": "c-sister", "alertId": "a-2", "state": "accepted", "notifiedAt": at(20), "acceptedAt": at(18),
          "assigneeMemberId": "m-sister", "assignee": ["memberId": "m-sister", "displayName": "妹"],
          "alert": alert(1, "sms", "銀行を名乗るSMS", "暗証番号の入力を求めるページに誘った"),
          "relays": [
            [
              "id": "r-1", "fromMemberId": "m-sister", "fromName": "妹", "createdAt": at(15),
              "body": "今から電話するね。番号は入れないで",
            ]
          ],
        ],
        [
          "id": "c-old", "alertId": "a-3", "state": "notified", "notifiedAt": at(40), "renotifiedAt": at(5),
          "alert": alert(2, "sms", "宅配の不在通知を名乗るSMS", "送り主の名前と違うドメインに誘った"),
          "relays": [],
        ],
      ]
    }

    func list() -> String {
      lock.withLock { ScreenshotStubTransport.json(["cases": cases]) }
    }

    /// `/cases/{id}/accept|relay|resolve`. The stub's member is "m-stub", shown as 作者.
    func act(path: String, body: String?) -> (Int, String) {
      let parts = path.split(separator: "/").map(String.init)
      guard parts.count == 3 else { return (404, "{}") }
      let (id, verb) = (parts[1], parts[2])
      return lock.withLock {
        guard let i = cases.firstIndex(where: { $0["id"] as? String == id }) else { return (404, "{}") }
        let now = Date.now.ISO8601Format()
        switch verb {
        case "accept":
          if cases[i]["state"] as? String != "notified" {
            let assignee = cases[i]["assignee"] ?? NSNull()
            return (409, ScreenshotStubTransport.json(["error": "already_accepted", "assignee": assignee]))
          }
          cases[i]["state"] = "accepted"
          cases[i]["acceptedAt"] = now
          cases[i]["assigneeMemberId"] = "m-stub"
          cases[i]["assignee"] = ["memberId": "m-stub", "displayName": "作者"]
        case "relay":
          var relays = cases[i]["relays"] as? [[String: Any]] ?? []
          relays.append([
            "id": UUID().uuidString, "fromMemberId": "m-stub", "fromName": "作者", "createdAt": now,
            "body": body ?? "",
          ])
          cases[i]["relays"] = relays
          return (201, ScreenshotStubTransport.json(["id": "r-new", "createdAt": now]))
        case "resolve":
          cases[i]["state"] = "resolved"
          cases[i]["resolvedAt"] = now
        default:
          return (404, "{}")
        }
        return (200, ScreenshotStubTransport.json(cases[i]))
      }
    }
  }
#endif
