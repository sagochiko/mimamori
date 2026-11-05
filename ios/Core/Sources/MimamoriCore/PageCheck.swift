import Foundation

/// The warning the Safari extension lays over a page. There is no "fine": no warning only means the
/// server's rules did not decide, or the check did not get through.
public enum PageWarning: Equatable, Sendable {
  /// Level 1, 開かないで.
  case doNotOpen
  /// Level 2, 家族に確かめるまで待って.
  case waitForFamily

  public var level: Int {
    switch self {
    case .doNotOpen: 1
    case .waitForFamily: 2
    }
  }
}

/// The parts of the Safari extension's page check that need no framework (ios/SafariExtension):
/// reading the message from the extension's JavaScript, building `POST /page` (server/src/page.ts),
/// reading its reply, and the reply back to the JavaScript.
///
/// The page's URL and text are data for the server's rules. They are never logged, and nothing in them
/// decides whether the check is sent or what the warning says.
public enum PageCheck {
  /// The server judges only the first 5,000 characters (docs/plan.md, task 9). Counted in Unicode
  /// scalars, as the server counts code points.
  public static let textMaxCharacters = 5000
  /// Kept short: Safari waits on the native handler, and a late warning is still drawn when it comes.
  public static let timeout: TimeInterval = 8
  private static let urlMaxCharacters = 8000

  /// `POST /page` for a message `{ type: "page", url, text }` from the background script, or nil for
  /// anything else (another scheme, another shape).
  public static func request(baseURL: URL, deviceKey: String, message: [String: Any]) -> URLRequest?
  {
    guard message["type"] as? String == "page",
      let urlText = message["url"] as? String, urlText.count <= urlMaxCharacters,
      let pageURL = URL(string: urlText),
      let scheme = pageURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
      pageURL.host != nil
    else { return nil }
    let rawText = message["text"] ?? ""
    guard let text = rawText as? String else { return nil }

    var cut = String.UnicodeScalarView()
    cut.append(contentsOf: text.unicodeScalars.prefix(textMaxCharacters))
    let body: [String: String] = ["url": urlText, "text": String(cut)]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }

    var request = URLRequest(url: baseURL.appendingPathComponent("page"), timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("Bearer \(deviceKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    return request
  }

  /// Reads `{ level: 1 | 2 | null, reasons }`. Anything other than a 2xx with level 1 or 2 is no warning.
  public static func warning(statusCode: Int?, data: Data?) -> PageWarning? {
    struct Reply: Decodable { let level: Int? }
    // JSONDecoder refuses `true` and `1.5` for an Int, which JSONSerialization would turn into 1.
    guard let statusCode, (200..<300).contains(statusCode), let data,
      let reply = try? JSONDecoder().decode(Reply.self, from: data)
    else { return nil }
    switch reply.level {
    case 1: return .doNotOpen
    case 2: return .waitForFamily
    default: return nil
    }
  }

  /// What the native handler hands back to the JavaScript: only the level, so no text from the server
  /// or the page is drawn on it.
  public static func reply(for warning: PageWarning?) -> [String: Any] {
    guard let warning else { return [:] }
    return ["level": warning.level]
  }
}

/// Sends the page check with this device's key. A failure of any kind is no warning; a 401 leaves the
/// stored key alone, since clearing it is the app's job (`APIClient`).
public struct PageChecker: Sendable {
  private let baseURL: URL
  private let transport: any HTTPTransport
  private let store: any DeviceKeyStore

  public init(
    baseURL: URL, transport: any HTTPTransport = URLSessionTransport(), store: any DeviceKeyStore
  ) {
    self.baseURL = baseURL
    self.transport = transport
    self.store = store
  }

  public func check(_ message: [String: Any]) async -> PageWarning? {
    guard let credentials = store.load(),
      let request = PageCheck.request(
        baseURL: baseURL, deviceKey: credentials.deviceKey, message: message)
    else { return nil }
    guard let (data, response) = try? await transport.send(request) else { return nil }
    return PageCheck.warning(statusCode: response.statusCode, data: data)
  }
}
