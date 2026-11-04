import Foundation

public enum APIError: Error, Equatable, Sendable {
  /// No device key is stored, so a call that needs one was not sent.
  case notJoined
  /// The server answered 401. The stored device key has already been cleared.
  case unauthorized
  /// Any other non-2xx answer.
  case http(status: Int)
  /// The answer was not in the expected shape.
  case invalidResponse
}

/// Calls the Workers API in docs/plan.md ("アプリと裏側の API").
///
/// Request bodies use snake_case (`display_name`) as in the plan; the shapes the plan left open
/// follow the task 2 server (branch issue-4-server-foundation).
/// Answers are read in camelCase (`deviceKey`, `familyId`) and also accepted in snake_case.
/// Calls made after joining send `Authorization: Bearer <deviceKey>`. A 401 clears the stored key
/// and calls `onUnauthorized`, so the app can go back to role selection.
public final class APIClient: Sendable {
  public let baseURL: URL
  private let transport: any HTTPTransport
  private let store: any DeviceKeyStore
  private let onUnauthorized: @Sendable () -> Void

  public init(
    baseURL: URL,
    transport: any HTTPTransport = URLSessionTransport(),
    store: any DeviceKeyStore,
    onUnauthorized: @escaping @Sendable () -> Void = {}
  ) {
    self.baseURL = baseURL
    self.transport = transport
    self.store = store
    self.onUnauthorized = onUnauthorized
  }

  // MARK: Calls

  /// `POST /families`. Creates a family and makes this device its first `family` member.
  @discardableResult
  public func createFamily(displayName: String) async throws -> Member {
    let answer: JoinAnswer = try await send(
      "POST", "families", body: NameBody(displayName: displayName), auth: false)
    return try keep(answer, displayName: displayName)
  }

  /// `POST /invites`. A new 6-digit code, valid for 24 hours.
  public func createInvite() async throws -> Invite {
    try await send("POST", "invites", body: Empty?.none, auth: true)
  }

  /// `POST /invites/{code}/join`. Joins with the given role and keeps the returned device key.
  @discardableResult
  public func join(code: InviteCode, role: Role, displayName: String) async throws -> Member {
    let answer: JoinAnswer = try await send(
      "POST", "invites/\(code.value)/join", body: JoinBody(role: role, displayName: displayName),
      auth: false
    )
    return try keep(answer, displayName: displayName)
  }

  /// `PUT /members/me/apns`. Registers this device's APNs token (sent as lowercase hex).
  public func registerAPNs(token: Data, environment: APNsEnvironment) async throws {
    let hex = token.map { String(format: "%02x", $0) }.joined()
    try await perform(
      "PUT", "members/me/apns", body: APNsBody(token: hex, env: environment), auth: true)
  }

  /// `GET /cases`. The family's recent cases, newest first.
  public func cases() async throws -> [Case] {
    let answer: CaseList = try await send("GET", "cases", body: Empty?.none, auth: true)
    return answer.cases
  }

  /// `POST /cases/{id}/resolve`. Any family member; pressing it again returns the case as it is.
  public func resolve(caseId: String) async throws -> Case {
    try await send("POST", "cases/\(caseId)/resolve", body: Empty?.none, auth: true)
  }

  /// `POST /consult`. What the protected person said, as text, with the earlier turns of the same
  /// conversation (left out when there are none); the answer to show and read aloud.
  public func consult(text: String, history: [ConsultTurn] = []) async throws -> ConsultAnswer {
    try await send(
      "POST", "consult", body: ConsultBody(text: text, history: history.isEmpty ? nil : history), auth: true)
  }

  // MARK: Plumbing

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom(decodeDate)
    return decoder
  }()

  private static let encoder = JSONEncoder()

  /// The answer does not echo the name back, so the member is built from what was sent.
  private func keep(_ answer: JoinAnswer, displayName: String) throws -> Member {
    try store.save(
      Credentials(
        deviceKey: answer.deviceKey,
        memberId: answer.memberId,
        familyId: answer.familyId,
        role: answer.role,
        familyToken: answer.familyToken
      ))
    return Member(id: answer.memberId, familyId: answer.familyId, role: answer.role, displayName: displayName)
  }

  private func send<Body: Encodable, Answer: Decodable>(
    _ method: String, _ path: String, body: Body?, auth: Bool
  ) async throws -> Answer {
    let data = try await perform(method, path, body: body, auth: auth)
    do {
      return try Self.decoder.decode(Answer.self, from: data)
    } catch {
      throw APIError.invalidResponse
    }
  }

  /// Sends one request and returns the body of a 2xx answer.
  @discardableResult
  private func perform<Body: Encodable>(
    _ method: String, _ path: String, body: Body?, auth: Bool
  ) async throws -> Data {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = try Self.encoder.encode(body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if auth {
      guard let key = store.load()?.deviceKey else { throw APIError.notJoined }
      request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await transport.send(request)

    switch response.statusCode {
    case 200..<300:
      return data
    case 401:
      store.clear()
      onUnauthorized()
      throw APIError.unauthorized
    default:
      throw APIError.http(status: response.statusCode)
    }
  }

  /// Dates may come as ISO 8601 (with or without fractional seconds) or as epoch milliseconds.
  private static func decodeDate(_ decoder: any Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    if let millis = try? container.decode(Double.self) {
      return Date(timeIntervalSince1970: millis / 1000)
    }
    let text = try container.decode(String.self)
    if let date = try? Date(text, strategy: .iso8601) { return date }
    if let date = try? Date(
      text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    {
      return date
    }
    throw DecodingError.dataCorruptedError(
      in: container, debugDescription: "unreadable date: \(text)")
  }
}

// MARK: Wire shapes

private struct Empty: Codable {}

/// `POST /families` and `POST /invites/{code}/join` both answer
/// `{familyId, memberId, deviceKey, familyToken, role}`; `familyToken` is 32 lowercase hex characters.
/// It stays optional here so an older server without it still lets the person join.
private struct JoinAnswer: Decodable {
  let familyId: String
  let memberId: String
  let deviceKey: String
  let role: Role
  let familyToken: String?
}

private struct CaseList: Decodable {
  let cases: [Case]
}

private struct ConsultBody: Encodable {
  let text: String
  /// Nil is left out of the JSON (Encodable skips nil optionals).
  let history: [ConsultTurn]?
}

private struct NameBody: Encodable {
  let displayName: String
  enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

private struct JoinBody: Encodable {
  let role: Role
  let displayName: String
  enum CodingKeys: String, CodingKey {
    case role
    case displayName = "display_name"
  }
}

/// `{token, env}`. `env` is always sent: the server treats a missing one as production,
/// and a Debug build's sandbox token would then be rejected by APNs.
private struct APNsBody: Encodable {
  let token: String
  let env: APNsEnvironment
}
