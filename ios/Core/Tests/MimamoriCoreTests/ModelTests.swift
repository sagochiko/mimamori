import Foundation
import Testing

@testable import MimamoriCore

@Suite("データの形")
struct ModelTests {
  /// One alert row; only `level` and `source` change between the cases below.
  private func alertJSON(level: String, source: String = #""sms""#) -> Data {
    Data(
      #"{"id":"a-1","source":\#(source),"level":\#(level),"reasons":[],"summary":"","createdAt":"2026-11-03T00:00:00Z"}"#
        .utf8)
  }

  @Test("危なさの 1、2、3 は読める", arguments: [(1, Level.doNotOpen), (2, .waitForFamily), (3, .lowConcern)])
  func readsLevels(raw: Int, level: Level) throws {
    #expect(Level.allCases.map(\.rawValue) == [1, 2, 3])
    let alert = try APIClient.decoder.decode(Alert.self, from: alertJSON(level: "\(raw)"))
    #expect(alert.level == level)
    #expect(alert.source == .sms)
  }

  @Test("危なさは 1、2、3 のほかを読まない(「安全」に落ちる道を作らない)", arguments: ["0", "4", "null", #""safe""#])
  func rejectsOtherLevels(bad: String) {
    #expect(throws: (any Error).self) {
      _ = try APIClient.decoder.decode(Alert.self, from: alertJSON(level: bad))
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

  @Test("決まった経路の知らせは読める", arguments: AlertSource.allCases)
  func readsKnownSources(source: AlertSource) throws {
    let alert = try APIClient.decoder.decode(
      Alert.self, from: alertJSON(level: "2", source: "\"\(source.rawValue)\""))
    #expect(alert.source == source)
    #expect(alert.level == .waitForFamily)
  }

  @Test("知らない経路の知らせは読めないことにする")
  func unknownSourceFails() {
    #expect(throws: (any Error).self) {
      _ = try APIClient.decoder.decode(Alert.self, from: alertJSON(level: "2", source: #""fax""#))
    }
  }

  @Test("相談を読む。解決した人はまだいなくてよい")
  func decodesCase() throws {
    let json = #"""
      {"id":"c-1","alertId":"a-1","state":"notified","resolvedBy":null,
       "notifiedAt":"2026-11-03T00:00:00.123Z","resolvedAt":null}
      """#
    let item = try APIClient.decoder.decode(Case.self, from: Data(json.utf8))
    #expect(item.state == .notified)
    #expect(item.resolvedBy == nil)
    #expect(item.resolvedAt == nil)
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
