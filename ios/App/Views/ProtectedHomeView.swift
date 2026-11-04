import MimamoriCore
import SwiftUI

/// The protected person's screen: what the family was told, then one big microphone. Pressing the
/// microphone and talking gets an answer, shown right above the microphone and read aloud. The AI
/// always answers; the family calls her when they want to talk. Explanations live in VoiceOver only.
struct ProtectedHomeView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  private static let consultID = "consult"
  /// Keeps what the microphone brought in view: while she talks and waits, and for the one reload of
  /// her notices that a handoff brings. Scrolling herself stops it.
  @State private var followsConsult = false

  var body: some View {
    let notices = model.protectedNotices
    VStack(spacing: 20) {
      // Scrolls instead of shortening a line: every word of an answer must be readable.
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
        // answer, so that one change moves it back into view too. Later changes (the 30-minute line, a
        // case resolved) leave the scroll where it is, so an old answer is not pulled back up.
        .onChange(of: model.voice.phase) { _, phase in
          followsConsult = phase.followsNotices
          reveal(phase, with: proxy)
        }
        .onChange(of: notices) {
          guard followsConsult else { return }
          reveal(model.voice.phase, with: proxy)
          if case .answered = model.voice.phase { followsConsult = false }
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

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(notice.status)
        .font(.title2.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint(hint)
      if let summary = notice.summary {
        Text(summary)
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("家族に伝えたこと、\(summary)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
  }

  private var hint: String {
    switch notice.status {
    case ProtectedNotice.notReached:
      "さっきの相談の知らせが、まだ家族のiPhoneに届いていません。送り直しています。急ぐときは家族に電話してください"
    case ProtectedNotice.noReplyYet:
      "30分たっても、家族が解決にしていません。急ぐときは家族に電話してください"
    default:
      "さっきの相談を家族に知らせました。家族から電話が来るかもしれません"
    }
  }
}
