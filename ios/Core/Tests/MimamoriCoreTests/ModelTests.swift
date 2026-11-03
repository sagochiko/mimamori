import Foundation
import Testing

@testable import MimamoriCore

@Suite("データの形")
struct ModelTests {
  @Test("危なさは 1、2、3 だけを読む")
  func levelsAreOneToThree() throws {
    #expect(Level.allCases.map(\.rawValue) == [1, 2, 3])
    for bad in ["0", "4", "null", #""safe""#] {
      let json =
        #"{"id":"a-1","source":"sms","level":\#(bad),"reasons":[],"summary":"","createdAt":"2026-11-03T00:00:00Z"}"#
      #expect(throws: (any Error).self, "level \(bad)") {
        _ = try APIClient.decoder.decode(Alert.self, from: Data(json.utf8))
      }
    }
  }

  @Test("知らせを読む")
  func decodesAlert() throws {
    let json = #"""
      {"id":"a-1","familyId":"f-1","source":"consult","level":1,"reasons":["警察を名乗ってお金の話"],
       "summary":"ニセ警察の疑い","createdAt":1793750400000}
      """#
    let alert = try APIClient.decoder.decode(Alert.self, from: Data(json.utf8))
    #expect(alert.level == .doNotOpen)
    #expect(alert.source == .consult)
    #expect(alert.reasons == ["警察を名乗ってお金の話"])
    #expect(alert.createdAt == Date(timeIntervalSince1970: 1_793_750_400))
  }

  @Test("知らない経路の知らせは読めないことにする")
  func unknownSourceFails() {
    let json =
      #"{"id":"a-1","source":"fax","level":2,"reasons":[],"summary":"","createdAt":"2026-11-03T00:00:00Z"}"#
    #expect(throws: (any Error).self) {
      _ = try APIClient.decoder.decode(Alert.self, from: Data(json.utf8))
    }
  }

  @Test("相談を読む。受け持ちはまだいなくてよい")
  func decodesCase() throws {
    let json = #"""
      {"id":"c-1","alertId":"a-1","state":"notified","assigneeMemberId":null,
       "notifiedAt":"2026-11-03T00:00:00.123Z","acceptedAt":null,"resolvedAt":null}
      """#
    let item = try APIClient.decoder.decode(Case.self, from: Data(json.utf8))
    #expect(item.state == .notified)
    #expect(item.assigneeMemberId == nil)
    #expect(item.acceptedAt == nil)
  }

  @Test("鍵がなければ役の選択から始める")
  func routeWithoutCredentials() {
    #expect(AppRoute(nil) == .chooseRole)
    #expect(
      AppRoute(Credentials(deviceKey: "k", memberId: "m", familyId: "f", role: .protected))
        == .protectedHome)
    #expect(
      AppRoute(Credentials(deviceKey: "k", memberId: "m", familyId: "f", role: .family))
        == .familyHome)
  }
}
