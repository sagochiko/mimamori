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
  @State private var writing = false
  /// Keeps the answer in view while the notices above it change after a handoff. Scrolling herself
  /// stops it.
  @State private var followsConsult = false
  /// From the opening until she scrolls or starts a consult: while the rows are still being laid
  /// out, the conversation keeps its end in view.
  @State private var opening = true
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var noticesOpen = false
  @State private var noticesHeight: CGFloat = 0
  /// Where the strip ends inside the top, so the top is never shorter than the closed strip (#134).
  @State private var stripBottom: CGFloat = 0
  @State private var screenHeight: CGFloat = 0
  @State private var camera = false
  @State private var choosingNote = false

  private static let liveID = "live"

  var body: some View {
    let notices = model.protectedNotices
    VStack(spacing: 0) {
      // Always there: the smiles row starts with the button that opens the smile camera.
      top(notices: notices)
      conversation(notices: notices)
      inputBar
    }
    .background(Color(.systemBackground))
    .onGeometryChange(for: CGFloat.self, of: \.size.height) { screenHeight = $0 }
    .task { await model.keepCasesFresh() }
    .task { await model.loadGmail() }
    .fullScreenCover(isPresented: $camera) { SmileCaptureView() }
    .sheet(isPresented: $choosingNote) {
      // Full height, and a swipe scrolls the words before it moves the sheet: at the medium height the
      // fifth word was cut off, and at the largest text size a swipe could not reach it.
      NoteSheet()
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
    }
    .onAppear {
      model.loadChat()
      model.refreshFollowUp()
      #if DEBUG
        if draft.isEmpty, let text = ScreenshotStubTransport.draftText { draft = text }
        if ScreenshotStubTransport.noticesOpen { noticesOpen = true }
        if ScreenshotStubTransport.cameraOpen { camera = true }
        if ScreenshotStubTransport.noteOpen { choosingNote = true }
      #endif
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      model.loadChat()
      model.refreshFollowUp()
      Task { await model.loadGmail() }
    }
  }

  /// The follow-up question, the family notices, and the smiles. Closed, the notices are one strip; open, the top
  /// takes at most 40% of the screen, scrolling beyond that, so the conversation always has room. The
  /// closed strip is never cut: at accessibility-extra-extra-extra-large it alone passed 40% and its
  /// line stopped at "急ぐなら" (#134), so there the top grows to the strip's end and the smiles and
  /// Gmail below it scroll.
  private func top(notices: [ProtectedNotice]) -> some View {
    ScrollView {
      VStack(spacing: 8) {
        if let prompt = model.followUpPrompt {
          FollowUpView(prompt: prompt)
        }
        if !notices.isEmpty {
          NoticeStrip(notices: notices, open: $noticesOpen)
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.topSpace)).maxY }) {
              stripBottom = $0
            }
        }
        // The family's smiles and replies, and her own (#14).
        SmileStrip(onCamera: { camera = true }, onNote: { choosingNote = true })
        // Only with no grant or one about to run out (Google ends it after 7 days); the family guides her.
        if model.offersGmail {
          Button("Gmail") { Task { await model.connectGmail() } }
            .font(.body)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Gmail をつなぐ")
            .accessibilityHint("Google の画面で許可すると、届いたメールに詐欺の疑いがないかをみまもりが見て、危ないときは家族に知らせます。許可は7日で切れるので、そのたびに取り直します")
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .onGeometryChange(for: CGFloat.self, of: \.size.height) { noticesHeight = $0 }
      .coordinateSpace(.named(Self.topSpace))
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: topHeight(hasNotices: !notices.isEmpty))
    .animation(.snappy, value: noticesOpen)
  }

  private static let topSpace = "top"

  private func topHeight(hasNotices: Bool) -> CGFloat {
    // The 8 points of padding under the strip, so its rounded bottom is not clipped.
    let closedStrip = hasNotices && !noticesOpen ? Double(stripBottom) + 8 : nil
    return CGFloat(
      ProtectedNotice.topHeight(
        content: Double(noticesHeight), screen: Double(screenHeight), closedStripBottom: closedStrip))
  }

  private func conversation(notices: [ProtectedNotice]) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 24) {
          ForEach(model.chat.log.rows(at: .now)) { row in
            switch row {
            case .day(let label, _):
              DayRow(label: label)
            case .message(let message, let time):
              ChatTurn(message: message, time: time).id(message.id)
            }
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
      .scrollPosition($position)
      .onChange(of: model.voice.phase) { _, phase in
        opening = false
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
        if phase == .interacting {
          followsConsult = false
          opening = false
        }
      }
      // The conversation opens at the newest, and then gets shorter from above or below: the notices
      // load and appear, open, or come up taller with a large text size, and the keyboard comes up.
      // If the newest was in view, it stays in view. Without this, at accessibility-large the newest
      // answer was left under the field from its fourth line on (#86). During a consult the reveal
      // above decides instead. While it opens, the content growing does the same: at
      // accessibility-large a conversation longer than the screen opened with the time under the
      // newest answer half under the field (#113). The bottom edge, padding included, is the target;
      // the empty live row was not enough.
      .onScrollGeometryChange(for: ConversationViewport.self, of: ConversationViewport.init) { old, new in
        let shrank = new.height != old.height
        let grew = opening && new.contentHeight != old.contentHeight
        guard shrank || grew, old.showsEnd || opening, !new.showsEnd, !followsConsult else { return }
        position.scrollTo(edge: .bottom)
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
      MessageField(
        text: $draft, isFocused: $writing, placeholder: "メッセージ", textStyle: .body, maxLines: 6,
        hint: "スマホの困りごとや気になる電話のことを書いて、送るボタンを押してください。答えは読み上げません"
      )
      .padding(.leading, 16)
      .padding(.vertical, 11)
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

  /// The glyphs in the field's 34pt circles grow with the text up to here; at the accessibility
  /// sizes they would spill out of the circle (seen at accessibility-large, 2026-11-05). There the
  /// large content viewer, on a long press, is the way to see them large.
  private static let largestButtonType = DynamicTypeSize.xxxLarge

  private var sendButton: some View {
    Button {
      guard canSend else { return }
      let text = draft
      draft = ""
      model.sendTyped(text)
    } label: {
      Image(systemName: "arrow.up")
        .font(.body.weight(.bold))
        .dynamicTypeSize(...Self.largestButtonType)
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Circle().fill(canSend ? Color.accentColor : Color.secondary))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!canSend)
    .transition(.scale.combined(with: .opacity))
    .accessibilityShowsLargeContentViewer { Label("送る", systemImage: "arrow.up") }
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
        .dynamicTypeSize(...Self.largestButtonType)
        .foregroundStyle(.white)
        .symbolEffect(.variableColor.iterative, isActive: listening)
        .frame(width: 34, height: 34)
        .background(Circle().fill(listening ? Color.red : Color.accentColor))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .transition(.scale.combined(with: .opacity))
    .accessibilityShowsLargeContentViewer {
      Label(model.voice.micLabel, systemImage: listening ? "waveform" : "mic.fill")
    }
    .accessibilityLabel(model.voice.micLabel)
    .accessibilityHint(model.voice.micHint)
  }
}

/// How tall the conversation's visible part is, and whether its end is in it.
private struct ConversationViewport: Equatable {
  let height: CGFloat
  let contentHeight: CGFloat
  let showsEnd: Bool

  init(_ geometry: ScrollGeometry) {
    height = geometry.containerSize.height
    contentHeight = geometry.contentSize.height
    // A point of slack for rounding.
    showsEnd = geometry.visibleRect.maxY >= geometry.contentSize.height - 1
  }
}

/// One turn of the conversation: the AI's answer as plain text across the width, her words in a
/// small grey bubble on the right, as in the AI chat apps (the author chose this on 2026-11-05, #87).
/// The time it was sent goes small beside her bubble and under the answer, as in the usual chat apps
/// (#113); a message kept without a time has none.
private struct ChatTurn: View {
  let message: ChatMessage
  let time: ChatStamp?
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    Group {
      if message.role == .protected {
        // At the accessibility sizes the time goes under the bubble: beside it, the bubble had about
        // five characters a line at accessibility-large (2026-11-06).
        if typeSize.isAccessibilitySize {
          VStack(alignment: .trailing, spacing: 4) {
            bubble
            stamp
          }
          .padding(.leading, 56)
          .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
          HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 56)
            stamp
            bubble
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text(message.text)
            .font(.body)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          stamp
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
  }

  private var bubble: some View {
    Bubble(text: message.text, fill: Color(.secondarySystemBackground), foreground: .primary)
  }

  @ViewBuilder private var stamp: some View {
    if let time {
      Text(time.text)
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize()
    }
  }

  private var label: String {
    let who = message.role == .protected ? "あなた" : "答え"
    guard let time else { return "\(who)、\(message.text)" }
    return "\(who)、\(message.text)、\(time.spoken)"
  }
}

/// Where the day changes: "11月4日", or "今日" (#113).
private struct DayRow: View {
  let label: String

  var body: some View {
    Text(label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(Capsule().fill(Color(.tertiarySystemFill)))
      .frame(maxWidth: .infinity)
      .accessibilityAddTraits(.isHeader)
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
          .padding(.vertical, 4)
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

/// The family notices in one strip: the most pressing one (`ProtectedNotice.mostPressing`), how many
/// there are, and a chevron. A tap opens every notice with what was passed to the family.
private struct NoticeStrip: View {
  let notices: [ProtectedNotice]
  @Binding var open: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if let first = ProtectedNotice.mostPressing(notices) {
      strip(first: first)
    }
  }

  /// Closed, a line that ends with "急ぐなら電話して" wraps as far as it needs, so "電話して" is never
  /// cut off on any width or text size: it took two lines on the iPhone 17 Pro simulator up to the
  /// largest standard size and three at accessibility-large (2026-11-05), and a narrower iPhone can
  /// need more. "家族に伝えました" stays within two lines below the accessibility sizes.
  private func closedLineLimit(_ first: ProtectedNotice) -> Int? {
    first.asksToCall || typeSize.isAccessibilitySize ? nil : 2
  }

  /// What a tap opens. "家族に伝えたこと" only when the most pressing one, and so every one, reached
  /// the family.
  private func closedHint(_ first: ProtectedNotice) -> String {
    first.asksToCall ? "押すと、相談を全部見られます" : "押すと、家族に伝えたことを全部見られます"
  }

  private func mark(_ first: ProtectedNotice) -> some View {
    Image(systemName: first.asksToCall ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
      .foregroundStyle(first.asksToCall ? Color.orange : Color.accentColor)
  }

  private func status(_ first: ProtectedNotice) -> some View {
    Text(first.status)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.primary)
      .lineLimit(open ? nil : closedLineLimit(first))
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var count: some View {
    if notices.count > 1 {
      Text("\(notices.count)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
  }

  private var chevron: some View {
    Image(systemName: "chevron.down")
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .rotationEffect(.degrees(open ? 180 : 0))
  }

  private func strip(first: ProtectedNotice) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        open.toggle()
      } label: {
        // At the accessibility sizes the line goes under the mark, the count, and the chevron, across the
        // whole width: beside them it had about four characters a line (#134).
        Group {
          if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 8) {
                mark(first)
                Spacer(minLength: 0)
                count
                chevron
              }
              status(first)
            }
          } else {
            HStack(spacing: 8) {
              mark(first)
              status(first)
              count
              chevron
            }
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        notices.count > 1 ? "\(first.status)、ほか\(notices.count - 1)件" : first.status
      )
      .accessibilityHint(open ? "押すと閉じます" : closedHint(first))
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
        .fill(first.asksToCall ? Color.orange.opacity(0.12) : Color(.secondarySystemBackground)))
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
