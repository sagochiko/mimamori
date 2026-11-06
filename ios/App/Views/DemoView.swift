import MimamoriCore
import SwiftUI

/// The judges' tour on one iPhone (#100): her screen and the family's card on the same screen. It
/// starts with the call follow-up; the microphone plays her fake-police consultation, the card the
/// family would get appears under it, and "解決" on the card or "30分後" shows both screens after
/// each. Then an SMS can be tried against `/sms/demo`. Nothing reaches any family: the consultation is
/// played on this iPhone and the SMS goes to `demo` without a device key (`DemoTour`, `DemoSMS`).
/// Only name tags and one-word buttons are on screen; the explanations are for VoiceOver.
struct DemoView: View {
  @State private var tour = DemoTour()
  @State private var noticesOpen = false

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // After "大丈夫" her screen has nothing left to show, so no empty frame.
          if tour.step != .fine {
            DemoSection(tag: "母", hint: "見守られる人のiPhoneに出る画面です") { motherScreen }
          }
          if let item = tour.familyCase {
            DemoSection(tag: "家族", hint: "家族のiPhoneに届く通知とカードです。本当の家族には送っていません") {
              if let push = tour.familyPush { DemoPushRow(push: push) }
              CaseCardView(card: FamilyCard(item)) { _ in
                withAnimation { tour.resolve(at: .now) }
              }
            }
          }
          if tour.canChoose {
            Button("30分後") {
              withAnimation { tour.waitHalfHour() }
            }
            .buttonStyle(BigButtonStyle(prominent: false))
            .accessibilityLabel("30分後")
            .accessibilityHint("家族の誰も解決を押さないまま30分たったときの、母と家族の画面にします。カードの解決を押すと、家族が解決したときの画面になります")
          }
          if tour.isFinished {
            DemoSMSSection(proxy: proxy)
            Button("最初から") {
              withAnimation {
                tour.restart()
                noticesOpen = false
              }
            }
            .buttonStyle(BigButtonStyle(prominent: false))
            .accessibilityHint("通話のあとの声かけからやり直します")
          }
        }
        .padding(16)
      }
      // The SMS field's keyboard closes with a drag, and "送る" closes it too, so the result is not hidden.
      .scrollDismissesKeyboard(.interactively)
    }
    .navigationBarTitleDisplayMode(.inline)
  }

  /// The top of her screen and her conversation, as `ProtectedHomeView` lays them out.
  private var motherScreen: some View {
    VStack(spacing: 16) {
      if let prompt = tour.prompt {
        FollowUpView(prompt: prompt) { withAnimation { tour.fine() } }
      }
      let notices = tour.protectedNotices(now: .now)
      if !notices.isEmpty {
        NoticeStrip(notices: notices, open: $noticesOpen)
      }
      ForEach(tour.messages) { message in
        ChatTurn(message: message, time: nil)
      }
      if tour.prompt != nil {
        Button {
          withAnimation { tour.consult(at: .now) }
        } label: {
          Image(systemName: "mic.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(Circle().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("話す")
        .accessibilityHint("母が警察を名乗る電話のことを AI に話したことにします。答えと家族に届くカードが出ます")
      }
    }
  }
}

/// A name tag ("母", "家族", "SMS") over a rounded area.
private struct DemoSection<Content: View>: View {
  let tag: String
  let hint: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(tag)
        .font(.headline)
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(hint)
      VStack(alignment: .leading, spacing: 12) { content }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator), lineWidth: 1))
    }
  }
}

/// The family's notification as the lock screen would show it: its title and its body.
private struct DemoPushRow: View {
  let push: DemoPush

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "bell.fill").foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(push.title).font(.subheadline.weight(.semibold))
        Text(push.body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.tertiarySystemFill)))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("家族に届く通知、\(push.title)、\(push.body)")
  }
}

/// An SMS from an unknown sender, judged by the server's rules at `/sms/demo`: where Apple would put
/// it, and the card the family would get. The text is the judge's to change.
private struct DemoSMSSection: View {
  /// Fictional: a look-alike domain under `.example` and a fake missed-delivery notice (as in eval/cases).
  static let sample =
    "【ヤマト運輸】お荷物のお届けにあがりましたが不在のため持ち帰りました。 https://kuroneko-redeliver.example/"

  let proxy: ScrollViewProxy
  private static let resultID = "sms-result"

  @State private var text = DemoSMSSection.sample
  @FocusState private var editing: Bool
  @State private var sending = false
  @State private var result: DemoSMSResult?
  @State private var card: Case?
  @State private var failed = false

  var body: some View {
    DemoSection(tag: "SMS", hint: "知らない相手からの SMS を、裏側の決まった規則で判定します。家族には知らせません") {
      TextField("SMS", text: $text, axis: .vertical)
        .lineLimit(3...8)
        .font(.body)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .accessibilityLabel("SMS の本文")
        .accessibilityHint("詐欺らしい SMS の例が入っています。書き換えて試せます")
        .focused($editing)
      Button("送る") {
        editing = false
        Task { await send() }
      }
      .buttonStyle(BigButtonStyle())
      .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityHint("この本文を、Apple が SMS を問い合わせるのと同じ形で裏側に送ります")
      if sending { ProgressView().frame(maxWidth: .infinity) }
      if failed {
        Text(Problem.unreachable.title)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityHint("裏側につながりませんでした。もう一度送ってください")
      }
      if let result {
        if result.verdict == .junk {
          Label("迷惑", systemImage: "xmark.bin.fill")
            .font(.headline)
            .foregroundStyle(.red)
            .accessibilityLabel("迷惑メッセージのフォルダへ")
            .accessibilityHint("規則ではっきり危ないので、iPhone は迷惑メッセージに振り分けます")
        }
        if let card {
          CaseCardView(card: FamilyCard(card)) { chosen in
            withAnimation { self.card = chosen.resolvedInDemo(at: .now) }
          }
        } else {
          Text("カードなし")
            .font(.headline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("家族へのカードなし")
            .accessibilityHint("決まった規則では家族に知らせる段階になりませんでした。安全という意味ではありません")
        }
      }
      Color.clear.frame(height: 1).id(Self.resultID)
    }
  }

  private func send() async {
    sending = true
    failed = false
    defer { sending = false }
    do {
      let answer = try await DemoSMS.check(
        text: text, baseURL: AppConfig.apiBaseURL, transport: URLSessionTransport(), at: .now)
      withAnimation {
        result = answer
        card = answer.card
      }
      try? await Task.sleep(for: .milliseconds(100))
      withAnimation { proxy.scrollTo(Self.resultID, anchor: .bottom) }
    } catch {
      result = nil
      card = nil
      failed = true
    }
  }
}
