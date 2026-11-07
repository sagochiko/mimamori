import Foundation
import Testing

@testable import MimamoriCore

@Suite("見守られる人が家族に入ったか")
struct ProtectedPresenceTests {
  static let morning = Date(timeIntervalSince1970: 1_793_000_000)

  static func smile(_ id: String, role: Role?, photo: Bool = true) -> Smile {
    Smile(
      id: id, memberId: "m-\(id)", displayName: "家族", role: role, score: nil, note: nil,
      hasPhoto: photo,
      createdAt: morning)
  }

  static let aCase = Case(
    id: "c-1", alertId: "a-1", state: .notified, notifiedAt: morning, familyNotifiedAt: morning)

  func make() -> (ProtectedPresence, InMemoryProtectedPresenceStore) {
    let store = InMemoryProtectedPresenceStore()
    return (ProtectedPresence(store: store), store)
  }

  @Test("笑顔も相談も無ければ、まだ入っていない")
  func nothingYet() {
    let (presence, _) = make()
    #expect(presence.hasJoined == false)
    #expect(presence.update(smiles: [], cases: []) == false)
  }

  @Test("家族の笑顔だけでは入ったことにしない")
  func familySmilesOnly() {
    let (presence, _) = make()
    #expect(
      presence.update(
        smiles: [Self.smile("a", role: .family), Self.smile("b", role: .family)], cases: [])
        == false)
  }

  @Test("抜けた人の笑顔(role が無い)は数えない")
  func leftMemberDoesNotCount() {
    let (presence, _) = make()
    #expect(presence.update(smiles: [Self.smile("a", role: nil)], cases: []) == false)
  }

  @Test("見守られる人の笑顔が1つあれば入った。写真の無いひと言の行でも数える")
  func protectedSmileCounts() {
    let (presence, _) = make()
    #expect(
      presence.update(
        smiles: [Self.smile("a", role: .family), Self.smile("m", role: .protected)], cases: []))
    let (other, _) = make()
    #expect(other.update(smiles: [Self.smile("m", role: .protected, photo: false)], cases: []))
  }

  @Test("相談が1件でもあれば入った(相談は見守られる人の端末からしか生まれない)")
  func caseCounts() {
    let (presence, _) = make()
    #expect(presence.update(smiles: [], cases: [Self.aCase]))
  }

  @Test("一度入ったと見えたら、笑顔が7日の窓から外れても戻らず、起動し直しても覚えている")
  func staysOnceSeen() {
    let (presence, store) = make()
    #expect(presence.update(smiles: [Self.smile("m", role: .protected)], cases: []))
    #expect(presence.update(smiles: [], cases: []))
    #expect(ProtectedPresence(store: store).hasJoined)
  }

  @Test("忘れると招待だけの画面に戻る")
  func forgetResets() {
    let (presence, store) = make()
    _ = presence.update(smiles: [], cases: [Self.aCase])
    presence.forget()
    #expect(presence.hasJoined == false)
    #expect(ProtectedPresence(store: store).hasJoined == false)
    #expect(presence.update(smiles: [], cases: []) == false)
  }

  @Test("「戻る」を押すと、笑顔も相談もまだ無くても入ったあとの画面になり、起動し直しても覚えている")
  func markJoinedShowsHome() {
    let (presence, store) = make()
    #expect(presence.update(smiles: [], cases: []) == false)
    presence.markJoined()
    #expect(presence.hasJoined)
    #expect(ProtectedPresence(store: store).hasJoined)
    #expect(presence.update(smiles: [], cases: []))
  }

  @Test("「戻る」のあとに家族を抜けたら忘れ、招待だけの画面に戻る")
  func markJoinedThenForget() {
    let (presence, store) = make()
    presence.markJoined()
    presence.forget()
    #expect(presence.hasJoined == false)
    #expect(ProtectedPresence(store: store).hasJoined == false)
    #expect(presence.update(smiles: [], cases: []) == false)
  }
}
