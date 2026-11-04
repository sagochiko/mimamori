import MimamoriCore
import SwiftUI

/// The protected person's screen, a chat like the messaging apps she already uses (#73, decided by
/// the author on 2026-11-04): what the family was told at the top, the conversation in the middle
/// (her words on the right, the AI's on the left, oldest first, opening at the newest), and a text
/// field with a microphone at the bottom. Voice and writing go into the same conversation; only an
/// answer to her voice is read aloud. Explanations live in VoiceOver only.
struct ProtectedHomeView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  @State private var draft = ""
  @FocusState private var writing: Bool
  /// Keeps the answer in view while the notices above it change after a handoff. Scrolling herself
  /// stops it.
  @State private var followsConsult = false
  @State private var noticesHeight: CGFloat = 0
  @State private var screenHeight: CGFloat = 0

  private static let liveID = "live"

  var body: some View {
    let notices = model.protectedNotices
    VStack(spacing: 0) {
      if model.followUpPrompt != nil || !notices.isEmpty {
        // At most 40% of the screen, so the conversation always has room; scrolls beyond that.
        ScrollView {
          VStack(spacing: 12) {
            if let prompt = model.followUpPrompt {
              FollowUpView(prompt: prompt)
            }
            ForEach(notices) { notice in
              NoticeView(notice: notice)
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .onGeometryChange(for: CGFloat.self, of: \.size.height) { noticesHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(noticesHeight, max(screenHeight * 0.4, 120)))
        Divider()
      }
      conversation(notices: notices)
      inputBar
    }
    .background(Color(.systemGroupedBackground))
    .onGeometryChange(for: CGFloat.self, of: \.size.height) { screenHeight = $0 }
    .task { await model.keepCasesFresh() }
    .onAppear {
      model.loadChat()
      model.refreshFollowUp()
      #if DEBUG
        if draft.isEmpty, let text = ScreenshotStubTransport.draftText { draft = text }
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      model.loadChat()
      model.refreshFollowUp()
    }
  }

  private func conversation(notices: [ProtectedNotice]) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 12) {
          ForEach(model.chat.log.messages) { message in
            ChatBubble(message: message).id(message.id)
          }
          // Always there, even while idle, so it can be scrolled to in the same update that shows
          // the first words heard.
          VStack(spacing: 0) {
            LiveView(phase: model.voice.phase)
          }
          .frame(maxWidth: .infinity)
          .id(Self.liveID)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
      // Opens at the newest. Growth is not anchored to the bottom: a long answer would then show its
      // end first.
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .defaultScrollAnchor(.bottom, for: .alignment)
      .onChange(of: model.voice.phase) { _, phase in
        followsConsult = phase.followsNotices
        reveal(phase, with: proxy)
      }
      // A handoff reloads her cases and adds a notice above, which makes the conversation shorter:
      // that one change brings the answer back into view too.
      .onChange(of: notices) {
        guard followsConsult else { return }
        reveal(model.voice.phase, with: proxy)
        if case .answered = model.voice.phase { followsConsult = false }
      }
      .onScrollPhaseChange { _, phase in
        if phase == .interacting { followsConsult = false }
      }
    }
  }

  /// Words being heard and the wait show at the bottom; an answer shows its first line.
  private func reveal(_ phase: ConsultPhase, with proxy: ScrollViewProxy) {
    switch phase {
    case .idle:
      return
    case .listening, .thinking, .failed:
      withAnimation { proxy.scrollTo(Self.liveID, anchor: .bottom) }
    case .answered:
      guard let last = model.chat.log.messages.last else { return }
      withAnimation { proxy.scrollTo(last.id, anchor: .top) }
    }
  }

  private var canSend: Bool {
    model.voice.acceptsText && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField("メッセージ", text: $draft, axis: .vertical)
        .font(.title3)
        .lineLimit(1...5)
        .focused($writing)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
          RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityHint("スマホの困りごとや気になる電話のことを書いて、送るボタンを押してください。答えは読み上げません")
      if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        sendButton
      }
      microphone
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
    .animation(.default, value: draft.isEmpty)
  }

  private var sendButton: some View {
    Button {
      guard canSend else { return }
      let text = draft
      draft = ""
      model.sendTyped(text)
    } label: {
      Image(systemName: "arrow.up")
        .font(.title2.bold())
        .foregroundStyle(.white)
        .frame(width: 48, height: 48)
        .background(Circle().fill(canSend ? Color.accentColor : Color.secondary))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .padding(.bottom, 8)
    .disabled(!canSend)
    .transition(.scale.combined(with: .opacity))
    .accessibilityLabel("送る")
    .accessibilityHint(model.voice.acceptsText ? "書いた言葉を送ります" : "答えを待っています")
  }

  /// Bigger than the send button: talking is the easiest way in.
  private var microphone: some View {
    let listening: Bool = {
      if case .listening = model.voice.phase { return true }
      return false
    }()
    return Button {
      writing = false
      model.micTapped()
    } label: {
      Image(systemName: listening ? "waveform" : "mic.fill")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(.white)
        .symbolEffect(.variableColor.iterative, isActive: listening)
        .frame(width: 64, height: 64)
        .background(Circle().fill(listening ? Color.red : Color.accentColor))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(model.voice.micLabel)
    .accessibilityHint(model.voice.micHint)
  }
}

/// One turn of the conversation: hers on the right, the AI's on the left.
private struct ChatBubble: View {
  let message: ChatMessage

  var body: some View {
    let mine = message.role == .protected
    HStack(spacing: 0) {
      if mine { Spacer(minLength: 48) }
      Text(message.text)
        .font(.title3)
        .foregroundStyle(mine ? Color.white : Color.primary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 20)
            .fill(mine ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
      if !mine { Spacer(minLength: 48) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(mine ? "あなた、\(message.text)" : "答え、\(message.text)")
  }
}

/// What is under way below the conversation: her words growing while the microphone listens, the
/// wait for an answer, or why it stopped. Nothing while idle or once answered (the answer is a turn).
private struct LiveView: View {
  let phase: ConsultPhase

  var body: some View {
    switch phase {
    case .idle, .answered:
      EmptyView()
    case .listening(let heard):
      if !heard.isEmpty {
        HStack(spacing: 0) {
          Spacer(minLength: 48)
          Text(heard)
            .font(.title3)
            .foregroundStyle(Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.opacity(0.18)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("聞き取っている言葉、\(heard)")
      }
    case .thinking:
      HStack(spacing: 0) {
        ProgressView()
          .controlSize(.large)
          .padding(.horizontal, 24)
          .padding(.vertical, 16)
          .background(
            RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        Spacer(minLength: 48)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("答えを考えています")
    case .failed(let failure):
      Text(failure.text)
        .font(.headline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint(failure.accessibilityHint)
    }
  }
}

/// "さっきの電話、大丈夫だった？" with one button. Talking or writing to the AI is the other answer.
private struct FollowUpView: View {
  let prompt: String
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(prompt)
        .font(.title3.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint("さっきの長い電話で気になることがあれば、マイクを押して話すか、下の欄に書いてください")
      Button("大丈夫") { model.followUpFine() }
        .font(.title3.bold())
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("押すと、この声かけを閉じます。家族には何も知らせません")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
  }
}

private struct NoticeView: View {
  let notice: ProtectedNotice

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(notice.status)
        .font(.title3.bold())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint(hint)
      if let summary = notice.summary, let label = notice.summaryLabel {
        Text(summary)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel(label)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
  }

  private var hint: String {
    switch notice.status {
    case ProtectedNotice.notReached:
      "さっきの相談の知らせが、まだ家族のiPhoneに届いていません。急ぐときは家族に電話してください"
    case ProtectedNotice.noReplyYet:
      "30分たっても、家族が解決にしていません。急ぐときは家族に電話してください"
    default:
      "さっきの相談を家族に知らせました。家族から電話が来るかもしれません"
    }
  }
}
