import MimamoriCore
import SwiftUI

/// The protected person's screen, a chat like the AI chat apps (#73, #86): what the family was told in
/// one thin strip at the top that opens on a tap, the conversation in the middle (the AI's answers as
/// plain text across the width, her words in small bubbles on the right, oldest first, opening at the
/// newest), and one slim field at the bottom with the microphone inside it. Voice and writing go into
/// the same conversation; only an answer to her voice is read aloud. Text follows Dynamic Type.
/// Explanations live in VoiceOver only.
struct ProtectedHomeView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  @State private var draft = ""
  @FocusState private var writing: Bool
  /// Keeps the answer in view while the notices above it change after a handoff. Scrolling herself
  /// stops it.
  @State private var followsConsult = false
  @State private var noticesOpen = false
  @State private var noticesHeight: CGFloat = 0
  @State private var screenHeight: CGFloat = 0

  private static let liveID = "live"
  private let look = ChatLook.current

  var body: some View {
    let notices = model.protectedNotices
    VStack(spacing: 0) {
      if model.followUpPrompt != nil || !notices.isEmpty {
        top(notices: notices)
      }
      conversation(notices: notices)
      inputBar
    }
    .background(Color(.systemBackground))
    .onGeometryChange(for: CGFloat.self, of: \.size.height) { screenHeight = $0 }
    .task { await model.keepCasesFresh() }
    .onAppear {
      model.loadChat()
      model.refreshFollowUp()
      #if DEBUG
        if draft.isEmpty, let text = ScreenshotStubTransport.draftText { draft = text }
        if ScreenshotStubTransport.noticesOpen { noticesOpen = true }
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      model.loadChat()
      model.refreshFollowUp()
    }
  }

  /// The follow-up question and the family notices. Closed, it is one line; open, at most 40% of the
  /// screen, scrolling beyond that, so the conversation always has room.
  private func top(notices: [ProtectedNotice]) -> some View {
    ScrollView {
      VStack(spacing: 8) {
        if let prompt = model.followUpPrompt {
          FollowUpView(prompt: prompt)
        }
        if !notices.isEmpty {
          NoticeStrip(notices: notices, open: $noticesOpen)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .onGeometryChange(for: CGFloat.self, of: \.size.height) { noticesHeight = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: min(noticesHeight, max(screenHeight * 0.4, 120)))
    .animation(.snappy, value: noticesOpen)
  }

  private func conversation(notices: [ProtectedNotice]) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: look.turnSpacing) {
          ForEach(model.chat.log.messages) { message in
            ChatTurn(message: message, look: look).id(message.id)
          }
          // Always there, even while idle, so it can be scrolled to in the same update that shows
          // the first words heard.
          VStack(spacing: 0) {
            LiveView(phase: model.voice.phase, look: look)
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

  private var hasDraft: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var canSend: Bool { model.voice.acceptsText && hasDraft }

  private var listening: Bool {
    if case .listening = model.voice.phase { return true }
    return false
  }

  /// One slim field. The button inside it is the microphone while the field is empty (or while
  /// listening) and the send button once she has written something, as in the AI chat apps.
  private var inputBar: some View {
    HStack(alignment: .bottom, spacing: 4) {
      TextField("メッセージ", text: $draft, axis: .vertical)
        .font(.body)
        .lineLimit(1...6)
        .focused($writing)
        .padding(.leading, 16)
        .padding(.vertical, 11)
        .accessibilityHint("スマホの困りごとや気になる電話のことを書いて、送るボタンを押してください。答えは読み上げません")
      Group {
        if hasDraft && !listening { sendButton } else { microphone }
      }
      .padding(.trailing, 4)
      .padding(.bottom, 4)
    }
    .background(Capsule().fill(Color(.secondarySystemBackground)))
    .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
    .animation(.snappy, value: hasDraft)
  }

  private var sendButton: some View {
    Button {
      guard canSend else { return }
      let text = draft
      draft = ""
      model.sendTyped(text)
    } label: {
      Image(systemName: "arrow.up")
        .font(.body.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Circle().fill(canSend ? Color.accentColor : Color.secondary))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!canSend)
    .transition(.scale.combined(with: .opacity))
    .accessibilityLabel("送る")
    .accessibilityHint(model.voice.acceptsText ? "書いた言葉を送ります" : "答えを待っています")
  }

  private var microphone: some View {
    Button {
      writing = false
      model.micTapped()
    } label: {
      Image(systemName: listening ? "waveform" : "mic.fill")
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .symbolEffect(.variableColor.iterative, isActive: listening)
        .frame(width: 34, height: 34)
        .background(Circle().fill(listening ? Color.red : Color.accentColor))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .transition(.scale.combined(with: .opacity))
    .accessibilityLabel(model.voice.micLabel)
    .accessibilityHint(model.voice.micHint)
  }
}

/// How the conversation is drawn. Debug builds can show the message-app look with
/// `-mimamori-look-bubbles`, to compare the two for #86; the choice then stays and the other goes.
enum ChatLook {
  /// The AI's answers as plain text across the width, her words in small grey bubbles.
  case plain
  /// Both in bubbles, hers in the accent color on the right, the AI's grey on the left.
  case bubbles

  static var current: ChatLook {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-mimamori-look-bubbles") { return .bubbles }
    #endif
    return .plain
  }

  var turnSpacing: CGFloat { self == .plain ? 24 : 12 }
}

/// One turn of the conversation.
private struct ChatTurn: View {
  let message: ChatMessage
  let look: ChatLook

  var body: some View {
    Group {
      if message.role == .protected {
        HStack(spacing: 0) {
          Spacer(minLength: 56)
          Bubble(
            text: message.text,
            fill: look == .plain ? Color(.secondarySystemBackground) : .accentColor,
            foreground: look == .plain ? .primary : .white)
        }
      } else if look == .plain {
        Text(message.text)
          .font(.body)
          .lineSpacing(3)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        HStack(spacing: 0) {
          Bubble(text: message.text, fill: Color(.secondarySystemBackground), foreground: .primary)
          Spacer(minLength: 56)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message.role == .protected ? "あなた、\(message.text)" : "答え、\(message.text)")
  }
}

private struct Bubble: View {
  let text: String
  let fill: Color
  let foreground: Color

  var body: some View {
    Text(text)
      .font(.body)
      .foregroundStyle(foreground)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(RoundedRectangle(cornerRadius: 18).fill(fill))
  }
}

/// What is under way below the conversation: her words growing while the microphone listens, the
/// wait for an answer, or why it stopped. Nothing while idle or once answered (the answer is a turn).
private struct LiveView: View {
  let phase: ConsultPhase
  let look: ChatLook

  var body: some View {
    switch phase {
    case .idle, .answered:
      EmptyView()
    case .listening(let heard):
      if !heard.isEmpty {
        HStack(spacing: 0) {
          Spacer(minLength: 56)
          Bubble(text: heard, fill: Color.accentColor.opacity(0.15), foreground: .primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("聞き取っている言葉、\(heard)")
      }
    case .thinking:
      HStack(spacing: 0) {
        ProgressView()
          .padding(.horizontal, look == .plain ? 0 : 18)
          .padding(.vertical, look == .plain ? 4 : 12)
          .background {
            if look == .bubbles {
              RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground))
            }
          }
        Spacer(minLength: 56)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("答えを考えています")
    case .failed(let failure):
      Text(failure.text)
        .font(.subheadline)
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
    HStack(spacing: 12) {
      Text(prompt)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("さっきの長い電話で気になることがあれば、マイクを押して話すか、下の欄に書いてください")
      Button("大丈夫") { model.followUpFine() }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .accessibilityHint("押すと、この声かけを閉じます。家族には何も知らせません")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
  }
}

/// The family notices in one line: the most pressing one, how many there are, and a chevron. A tap
/// opens every notice with what was passed to the family.
private struct NoticeStrip: View {
  let notices: [ProtectedNotice]
  @Binding var open: Bool

  var body: some View {
    let first = Self.mostPressing(notices)
    VStack(alignment: .leading, spacing: 0) {
      Button {
        open.toggle()
      } label: {
        HStack(spacing: 8) {
          Image(
            systemName: Self.urgent(first) ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
          )
          .foregroundStyle(Self.urgent(first) ? Color.orange : Color.accentColor)
          Text(first.status)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(open ? nil : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
          if notices.count > 1 {
            Text("\(notices.count)")
              .font(.caption.weight(.semibold))
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Capsule().fill(Color(.tertiarySystemFill)))
          }
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(open ? 180 : 0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        notices.count > 1 ? "\(first.status)、ほか\(notices.count - 1)件" : first.status
      )
      .accessibilityHint(open ? "押すと閉じます" : "押すと、家族に伝えたことを全部見られます")
      if open {
        Divider().padding(.leading, 16)
        VStack(alignment: .leading, spacing: 12) {
          ForEach(notices) { notice in
            NoticeRow(notice: notice)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .transition(.opacity)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Self.urgent(first) ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground)))
  }

  static func urgent(_ notice: ProtectedNotice) -> Bool {
    notice.status != ProtectedNotice.toldFamily
  }

  /// Not reached first, then no reply yet, then told; newest first within each.
  static func mostPressing(_ notices: [ProtectedNotice]) -> ProtectedNotice {
    func rank(_ n: ProtectedNotice) -> Int {
      switch n.status {
      case ProtectedNotice.notReached: 0
      case ProtectedNotice.noReplyYet: 1
      default: 2
      }
    }
    return notices.enumerated().min {
      (rank($0.element), $0.offset) < (rank($1.element), $1.offset)
    }!.element
  }
}

private struct NoticeRow: View {
  let notice: ProtectedNotice

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(notice.status)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHint(hint)
      if let summary = notice.summary, let label = notice.summaryLabel {
        Text(summary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel(label)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
