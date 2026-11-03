import Foundation
import Testing

@testable import MimamoriCore

/// A transport that records requests and answers with canned responses. No real network.
final class StubTransport: HTTPTransport, @unchecked Sendable {
  struct Reply {
    var status: Int
    var body: String
  }

  private let lock = NSLock()
  private var replies: [Reply]
  private var _requests: [URLRequest] = []

  init(_ replies: [Reply]) {
    self.replies = replies
  }

  convenience init(status: Int, body: String = "{}") {
    self.init([Reply(status: status, body: body)])
  }

  var requests: [URLRequest] {
    lock.withLock { _requests }
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let reply: Reply = lock.withLock {
      _requests.append(request)
      return replies.count > 1 ? replies.removeFirst() : replies[0]
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    return (Data(reply.body.utf8), response)
  }
}

/// Counts how many times the client reported a 401.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value = 0
  var value: Int { lock.withLock { _value } }
  func increment() { lock.withLock { _value += 1 } }
}

extension Credentials {
  static let sample = Credentials(
    deviceKey: "dk_test_0123456789",
    memberId: "m-1",
    familyId: "f-1",
    role: .family
  )
}

let testBaseURL = URL(string: "https://api.test.invalid")!

func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
  let data = try #require(request.httpBody)
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// An install marker that lives in memory. `markedOnDisk` is what a later read would find.
final class InMemoryInstallMarker: InstallMarkerStore, @unchecked Sendable {
  var markedOnDisk: Bool
  init(marked: Bool) { markedOnDisk = marked }
  var isMarked: Bool { markedOnDisk }
  func mark() -> Bool {
    markedOnDisk = true
    return true
  }
}

/// A marker that cannot be written, as when the disk is full.
final class UnwritableInstallMarker: InstallMarkerStore, @unchecked Sendable {
  private(set) var attempts = 0
  var isMarked: Bool { false }
  func mark() -> Bool {
    attempts += 1
    return false
  }
}
