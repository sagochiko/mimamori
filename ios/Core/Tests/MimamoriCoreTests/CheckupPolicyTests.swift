import Foundation
import Testing

@testable import MimamoriCore

@Suite("アプリからの声かけ(空き容量)")
struct CheckupPolicyTests {
  static let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }()

  /// 2026年11月7日の、東京の時刻で hour:minute。
  static func at(_ hour: Int, _ minute: Int = 0, day: Int = 7) -> Date {
    tokyo.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  static let low: Int64 = 800_000_000
  static let plenty: Int64 = 20_000_000_000

  func make() -> (CheckupPolicy, InMemoryCheckupStore) {
    let store = InMemoryCheckupStore()
    return (CheckupPolicy(store: store, calendar: Self.tokyo), store)
  }

  @Test("空きが少ないと声をかけ、空きの量を GB で見せる")
  func lowSpaceNotifies() {
    let (policy, _) = make()
    let action = policy.storageChecked(availableBytes: Self.low, at: Self.at(10))
    #expect(action == .notify(CheckupPolicy.storagePrompt(availableBytes: Self.low)))
    #expect(CheckupPolicy.storagePrompt(availableBytes: Self.low).contains("0.8GB"))
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(10, 1)) != nil)
  }

  @Test("空きが足りていれば何もしない。読めなかったときも何もしない")
  func enoughOrUnknownIsQuiet() {
    let (policy, _) = make()
    #expect(policy.storageChecked(availableBytes: Self.plenty, at: Self.at(10)) == .nothing)
    #expect(policy.storageChecked(availableBytes: nil, at: Self.at(10)) == .nothing)
    #expect(
      policy.storageChecked(availableBytes: CheckupPolicy.lowStorageBytes, at: Self.at(10))
        == .nothing)
    #expect(
      policy.storageChecked(availableBytes: CheckupPolicy.lowStorageBytes - 1, at: Self.at(10))
        != .nothing)
  }

  @Test("同じ点検の声かけは1日1回まで。次の日はまた声をかける")
  func oncePerDay() {
    let (policy, _) = make()
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(8)) != .nothing)
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(12)) == .nothing)
    #expect(policy.storageChecked(availableBytes: Self.low / 2, at: Self.at(21, 59)) == .nothing)
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(7, 0, day: 8)) != .nothing)
  }

  @Test("夜22時から朝7時は通知も画面の声かけも出さず、その日の1回も使わない")
  func quietAtNight() {
    let (policy, _) = make()
    for date in [Self.at(22), Self.at(23, 30), Self.at(0, 0, day: 8), Self.at(6, 59, day: 8)] {
      #expect(policy.storageChecked(availableBytes: Self.low, at: date) == .nothing)
      #expect(policy.storagePromptToShow(availableBytes: Self.low, at: date) == nil)
    }
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(7, 0, day: 8)) != .nothing)
  }

  @Test("昼に声をかけたあと、夜になると画面の声かけも隠れ、朝にまた出る")
  func promptHidesAtNight() {
    let (policy, _) = make()
    _ = policy.storageChecked(availableBytes: Self.low, at: Self.at(21))
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(21, 30)) != nil)
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(22, 30)) == nil)
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(7, 30, day: 8)) != nil)
  }

  @Test("「あとで」を押したら24時間は通知も画面の声かけも出さない")
  func laterSnoozes24Hours() {
    let (policy, _) = make()
    _ = policy.storageChecked(availableBytes: Self.low, at: Self.at(10))
    policy.later(at: Self.at(10, 5))
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(10, 6)) == nil)
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(10, 4, day: 8)) == .nothing)
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(10, 4, day: 8)) == nil)
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(10, 5, day: 8)) != .nothing)
  }

  @Test("空きが戻ったら画面の声かけは消える")
  func clearsWhenFreed() {
    let (policy, _) = make()
    _ = policy.storageChecked(availableBytes: Self.low, at: Self.at(10))
    #expect(policy.storageChecked(availableBytes: Self.plenty, at: Self.at(11)) == .nothing)
    #expect(policy.storagePromptToShow(availableBytes: Self.plenty, at: Self.at(11)) == nil)
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(11, 1)) == nil)
  }

  @Test("声かけから相談に入ると、設定の「iPhoneストレージ」への案内から始まり、声かけは閉じる")
  func startGuide() {
    let (policy, _) = make()
    _ = policy.storageChecked(availableBytes: Self.low, at: Self.at(10))
    let guide = policy.startStorageGuide()
    #expect(guide == CheckupPolicy.storageGuide)
    #expect(guide.contains("設定"))
    #expect(guide.contains("一般"))
    #expect(guide.contains("iPhoneストレージ"))
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(10, 1)) == nil)
    // Opening the guide is the day's prompt answered; it does not come back that day.
    #expect(policy.storageChecked(availableBytes: Self.low, at: Self.at(15)) == .nothing)
  }

  @Test("案内の文には空きの量も数字も入れない。会話の続きと一緒に端末の外へ出るため")
  func guideCarriesNoAmount() {
    // Decimal digits of any width; 一 in 一緒 and 一般 is a word, not an amount.
    let digits = CheckupPolicy.storageGuide.unicodeScalars.filter { $0.properties.generalCategory == .decimalNumber }
    #expect(digits.isEmpty)
  }

  @Test("覚えておく中身に空きの量は入らない")
  func stateKeepsNoAmount() throws {
    let (policy, store) = make()
    let odd: Int64 = 812_345_678
    _ = policy.storageChecked(availableBytes: odd, at: Self.at(10))
    policy.later(at: Self.at(10, 1))
    _ = policy.storageChecked(availableBytes: odd, at: Self.at(11, 0, day: 8))
    let json = String(decoding: try JSONEncoder().encode(store.load()), as: UTF8.self)
    #expect(!json.contains("812345678"))
    #expect(!json.contains("0.8"))
    #expect(!json.contains("GB"))
  }

  @Test("忘れると、覚えていたことは消える(すべて消す、401、家族を抜けたとき)")
  func forget() {
    let (policy, store) = make()
    _ = policy.storageChecked(availableBytes: Self.low, at: Self.at(10))
    policy.forget()
    #expect(store.load() == CheckupState())
    #expect(policy.storagePromptToShow(availableBytes: Self.low, at: Self.at(10, 1)) == nil)
  }
}

@Suite("生存の知らせ")
struct HeartbeatTests {
  @Test("送るのは通知とバックグラウンド更新の真偽だけで、空き容量は送らない")
  func bodyHasOnlyTwoBooleans() async throws {
    let transport = StubTransport(status: 204, body: "")
    let client = APIClient(baseURL: testBaseURL, transport: transport, store: InMemoryDeviceKeyStore(.sample))
    try await client.heartbeat(HeartbeatReport(notificationsOn: false, backgroundRefreshOn: true))
    let request = try #require(transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/heartbeat")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer dk_test_0123456789")
    let object = try bodyJSON(request)
    #expect(Set(object.keys) == ["notifications", "backgroundRefresh"])
    #expect(object["notifications"] as? Bool == false)
    #expect(object["backgroundRefresh"] as? Bool == true)
  }

  @Test("前に送ってから6時間たつまでは送り直さない。設定が変わったらすぐ送る")
  func throttle() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let on = HeartbeatReport(notificationsOn: true, backgroundRefreshOn: true)
    var gate = HeartbeatGate()
    #expect(gate.shouldSend(on, at: start))
    gate.sent(on, at: start)
    #expect(!gate.shouldSend(on, at: start.addingTimeInterval(5 * 3600)))
    #expect(gate.shouldSend(on, at: start.addingTimeInterval(6 * 3600)))
    let off = HeartbeatReport(notificationsOn: false, backgroundRefreshOn: true)
    #expect(gate.shouldSend(off, at: start.addingTimeInterval(60)))
  }
}
