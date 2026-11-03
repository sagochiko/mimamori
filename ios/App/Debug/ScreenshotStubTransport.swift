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
#endif
