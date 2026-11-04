import MimamoriCore
import SwiftUI

/// The protected person's screen: what the family was told and their replies, then one big
/// microphone. Replies are read aloud once when they arrive; tapping one reads it again. Pressing the
/// microphone and talking gets an answer, shown right above the microphone and read aloud.
/// Explanations live in VoiceOver only.
struct ProtectedHomeView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  private static let consultID = "consult"
  /// Keeps what the microphone brought in view until she scrolls herself.
  @State private var followsConsult = false

  var body: some View {
    let notices = model.protectedNotices
    VStack(spacing: 20) {
      // Scrolls instead of shortening a line: every word of a reply must be readable.
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 16) {
            if let prompt = model.followUpPrompt {
              FollowUpView(prompt: prompt)
            }
            ForEach(notices) { notice in
              NoticeView(notice: notice)
            }
            // Last, next to the microphone. The container is always there, even while idle, so it
            // can be scrolled to in the same update that shows the first words.
            VStack(spacing: 0) {
              ConsultView(phase: model.voice.phase)
            }
            .frame(maxWidth: .infinity)
            .id(Self.consultID)
          }
        }
        .scrollBounceBehavior(.basedOnSize)
        // Opens at the latest, next to the microphone, and sits there while it is short. Growth is not
        // anchored to the bottom: a long answer would then show its end first.
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        // Whatever the microphone brought (words heard, thinking, the answer, a failure), she sees it
        // without scrolling, at any text size. A handoff reloads her cases and adds a notice above the
        // answer, so that moves it back into view too, until she scrolls herself.
        .onChange(of: model.voice.phase) { _, phase in
          followsConsult = phase != .idle
          reveal(phase, with: proxy)
        }
        .onChange(of: notices) {
          if followsConsult { reveal(model.voice.phase, with: proxy) }
        }
        .onScrollPhaseChange { _, phase in
          if phase == .interacting { followsConsult = false }
        }
      }
      microphone
    }
    .padding(24)
    .task { await model.keepCasesFresh() }
    .onAppear { model.refreshFollowUp() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshFollowUp() }
    }
  }

  /// Words being heard show their latest end; anything else shows its first line at the top.
  private func reveal(_ phase: ConsultPhase, with proxy: ScrollViewProxy) {
    switch phase {
    case .idle:
      return
    case .listening:
      proxy.scrollTo(Self.consultID, anchor: .bottom)
    case .thinking, .answered, .failed:
      withAnimation { proxy.scrollTo(Self.consultID, anchor: .top) }
    }
  }

  private var microphone: some View {
    let listening: Bool = {
      if case .listening = model.voice.phase { return true }
      return false
    }()
    return Button {
      model.micTapped()
    } label: {
      Image(systemName: listening ? "waveform" : "mic.fill")
        .font(.system(size: 88, weight: .semibold))
        .foregroundStyle(.white)
        .symbolEffect(.variableColor.iterative, isActive: listening)
        .frame(width: 200, height: 200)
        .background(Circle().fill(listening ? Color.red : Color.accentColor))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(model.voice.micLabel)
    .accessibilityHint(model.voice.micHint)
  }
}

/// "さっきの電話、大丈夫だった？" with one button. Talking to the microphone is the other answer.
private struct FollowUpView: View {
  let prompt: String
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(prompt)
        .font(.title2.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint("さっきの長い電話で気になることがあれば、マイクを押して話してください")
      Button("大丈夫") { model.followUpFine() }
        .font(.title2.bold())
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("押すと、この声かけを閉じます。家族には何も知らせません")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
  }
}

/// What she is saying while the microphone listens, then the answer. Nothing while idle.
private struct ConsultView: View {
  let phase: ConsultPhase

  var body: some View {
    switch phase {
    case .idle:
      EmptyView()
    case .listening(let heard):
      if !heard.isEmpty {
        Text(heard)
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("聞き取っている言葉、\(heard)")
      }
    case .thinking:
      ProgressView()
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("答えを考えています")
    case .answered(let said, let answer):
      Text(answer.reply)
        .font(.title2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.accentColor.opacity(0.15)))
        .accessibilityLabel(answer.reply)
        .accessibilityHint("「\(said)」への答えです。もう一度相談するときは、マイクを押してください")
    case .failed(let failure):
      Text(failure.text)
        .font(.title2.bold())
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint(failure.accessibilityHint)
    }
  }
}

private struct NoticeView: View {
  let notice: ProtectedNotice
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let status = notice.status {
        Text(status)
          .font(.title2.bold())
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityHint(hint(for: status))
      }
      if let summary = notice.summary {
        Text(summary)
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("家族に伝えたこと、\(summary)")
      }
      if let reply = notice.reply {
        Button {
          model.speakAgain(reply)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(reply.from).font(.title3.bold())
            Text(reply.body).font(.title2).fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("家族が書いた返事です。押すともう一度読み上げます")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
  }

  private func hint(for status: String) -> String {
    switch status {
    case ProtectedNotice.toldFamily: "さっきの相談を家族に知らせました。家族が見たら、ここに名前が出ます"
    case ProtectedNotice.noReplyYet: "30分たっても家族が引き受けていません。急ぐときは家族に電話してください"
    default: "家族がこの相談を引き受けました。返事を待ってください"
    }
  }
}
