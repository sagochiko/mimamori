import MimamoriCore
import PhotosUI
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
  /// The photo button's picker (#221). PhotosPicker runs outside the app and hands over only the
  /// picked image, so no photo library permission is asked.
  @State private var choosingPhoto = false
  @State private var pickedPhoto: PhotosPickerItem?

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
    .photosPicker(isPresented: $choosingPhoto, selection: $pickedPhoto, matching: .images)
    .onChange(of: pickedPhoto) { _, item in
      guard let item else { return }
      pickedPhoto = nil
      Task {
        let data = try? await item.loadTransferable(type: Data.self)
        guard let data else {
          model.pictureUnreadable()
          return
        }
        picked(data)
      }
    }
    .onAppear {
      model.loadChat()
      model.refreshFollowUp()
      model.refreshCheckup()
      #if DEBUG
        if draft.isEmpty, let text = ScreenshotStubTransport.draftText { draft = text }
        if ScreenshotStubTransport.noticesOpen { noticesOpen = true }
        if ScreenshotStubTransport.cameraOpen { camera = true }
        if ScreenshotStubTransport.photoOpen { choosingPhoto = true }
        // After the draft, so `-mimamori-stub-photo-send` sends the words of `-mimamori-stub-draft`
        // with the image.
        if ScreenshotStubTransport.photoPick { picked(StubPicture.settingsScreen()) }
        if ScreenshotStubTransport.photoPick, ScreenshotStubTransport.photoSend { send() }
        if ScreenshotStubTransport.listening, !listening { model.micTapped() }
      #endif
    }
    // The stop button of the recording field put her words here, to fix and send.
    .onChange(of: model.voiceDraft) { _, words in
      guard words != nil, let words = model.takeVoiceDraft() else { return }
      draft = words
    }
    .onChange(of: draft) { _, text in
      if text.isEmpty { model.draftCleared() }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      model.loadChat()
      model.refreshFollowUp()
      model.refreshCheckup()
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
          FollowUpView(prompt: prompt) { model.followUpAcknowledged() }
        }
        if let prompt = model.checkupPrompt {
          CheckupView(prompt: prompt, onLater: { model.checkupLater() }, onStart: { model.startStorageGuide() })
        }
        if !notices.isEmpty {
          NoticeStrip(notices: notices, open: $noticesOpen)
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.topSpace)).maxY }) {
              stripBottom = $0
            }
        }
        // The family's smiles only, as thin as the strip (#14, set words dropped in #223, her own and
        // the protected role's dropped in #243). The menu with "設定" and "家族を削除" (#190, #279) is the row's last
        // item, so her screen gets no navigation bar and no extra line, and the row still runs to the
        // edge of the screen.
        SmileStrip(onCamera: { camera = true }, showsMenu: true, compact: true)
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
              ChatTurn(message: message, time: time) { model.chat.picture(for: message) }
                .id(message.id)
              if let shown = model.shownPicture, shown.anchor == message.id {
                ShownPictureView(shown: shown)
              }
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
        // Shrinking follows only when the end was in view: after VoiceOver's three-finger scroll or a
        // tap on the status bar, which do not end `opening`, it does not pull her back down.
        let shrank = new.height != old.height && old.showsEnd
        let grew = opening && new.contentHeight != old.contentHeight
        guard shrank || grew, !new.showsEnd, !followsConsult else { return }
        position.scrollTo(edge: .bottom)
      }
    }
  }

  /// Words being heard and the wait show at the bottom; an answer shows its first line.
  private func reveal(_ phase: ConsultPhase, with proxy: ScrollViewProxy) {
    switch phase {
    case .idle:
      return
    case .thinking where model.shownPicture != nil:
      // Her line with the image under it can be taller than the screen; lined up at the bottom it
      // pushed her own bubble up out of view. Her line goes at the top instead (review 1 of PR #237).
      guard let anchor = model.shownPicture?.anchor else { return }
      withAnimation { proxy.scrollTo(anchor, anchor: .top) }
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

  private var canSend: Bool { model.voice.canSend(draft: draft) }

  private var listening: Bool {
    if case .listening = model.voice.phase { return true }
    return false
  }

  /// One slim field. The button inside it is the microphone while the field is empty and the send
  /// button once she has written something, as in the AI chat apps. While listening the whole field is
  /// the recording field instead (#224).
  private var inputBar: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let picture = model.attachedPicture {
        AttachedPictureView(picture: picture) { model.removePicture() }
          .padding(.leading, 8)
          .transition(.opacity)
      }
      Group {
        if listening { recordingBar } else { writingBar }
      }
      .background(Capsule().fill(Color(.secondarySystemBackground)))
      .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
      .guideTarget(.talk)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
    .animation(.snappy, value: hasDraft)
    .animation(.snappy, value: listening)
    .animation(.snappy, value: model.attachedPicture != nil)
  }

  /// As in the usual chat apps' recording field (the author sent one as the model on 2026-11-07,
  /// #224): trash, the time, dots that follow her voice, stop, send. No words on the buttons; VoiceOver
  /// has them. The words heard so far still grow in her bubble in the conversation (`LiveView`).
  private var recordingBar: some View {
    HStack(spacing: 4) {
      roundButton(
        systemImage: "trash", label: RecordingBar.discardLabel, hint: RecordingBar.discardHint,
        foreground: .secondary, fill: nil
      ) { model.recordingDiscardTapped() }
      .padding(.leading, 4)
      RecordingClockView(since: model.voice.listeningSince)
      VoiceLevelDots()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
      roundButton(
        systemImage: "stop.fill", label: RecordingBar.stopLabel, hint: RecordingBar.stopHint,
        foreground: .primary, fill: Color(.tertiarySystemFill)
      ) { model.recordingStopTapped() }
      roundButton(
        systemImage: "arrow.up", label: RecordingBar.sendLabel, hint: RecordingBar.sendHint,
        foreground: .white, fill: Color.accentColor
      ) { model.recordingSendTapped() }
      .padding(.trailing, 4)
    }
    .padding(.vertical, 4)
    .transition(.opacity)
  }

  /// A glyph in a 34pt circle with a 44pt target, like the field's other buttons.
  private func roundButton(
    systemImage: String, label: String, hint: String, foreground: Color, fill: Color?,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.body.weight(.bold))
        .dynamicTypeSize(...Self.largestButtonType)
        .foregroundStyle(foreground)
        .frame(width: 34, height: 34)
        .background(Circle().fill(fill ?? Color.clear))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityShowsLargeContentViewer { Label(label, systemImage: systemImage) }
    .accessibilityLabel(label)
    .accessibilityHint(hint)
  }

  private var writingBar: some View {
    HStack(alignment: .bottom, spacing: 4) {
      photoButton
        .guideTarget(.photo)
        .padding(.leading, 4)
        .padding(.bottom, 4)
      MessageField(
        text: $draft, isFocused: $writing, placeholder: "相談・質問を入力してね", textStyle: .body, maxLines: 6,
        hint: model.voice.hasVoiceDraft
          ? "聞き取った言葉が入っています。直してから送るボタンを押してください。声で聞いたときと同じに扱います"
          : model.attachedPicture != nil
            ? "付けたスクショで何をしたいかを書いて、送るボタンを押してください。マイクで話しても一緒に送ります。書かずに送ると、スクショだけを送ります"
            : "スマホの困りごとや気になる電話のことを書いて、送るボタンを押してください。答えは読み上げません",
        // A screenshot copied and pasted into the field goes onto it like a picked one (#243).
        onPasteImage: model.voice.acceptsText ? { picked($0) } : nil
      )
      .padding(.vertical, 11)
      Group {
        if hasDraft {
          sendButton
        } else if model.attachedPicture != nil {
          // An image alone can go (#243); the microphone stays, to say what she wants with it.
          HStack(spacing: 0) {
            microphone
            sendButton
          }
        } else {
          microphone
        }
      }
      .padding(.trailing, 4)
      .padding(.bottom, 4)
    }
  }

  /// The glyphs in the field's 34pt circles grow with the text up to here; at the accessibility
  /// sizes they would spill out of the circle (seen at accessibility-large, 2026-11-05). There the
  /// large content viewer, on a long press, is the way to see them large.
  private static let largestButtonType = DynamicTypeSize.xxxLarge

  private var sendButton: some View {
    Button {
      send()
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
    .accessibilityHint(
      model.voice.acceptsText
        ? (model.attachedPicture != nil
          ? (hasDraft ? "付けたスクショと書いた言葉を一緒に送ります" : "付けたスクショだけを送ります")
          : model.voice.hasVoiceDraft ? "聞き取った言葉を送ります" : "書いた言葉を送ります")
        : "答えを待っています")
  }

  /// The send button: her words, with the image on the field if there is one (#234).
  private func send() {
    guard canSend else { return }
    let text = draft
    draft = ""
    model.sendTyped(text)
  }

  /// The image she picked goes onto the field and waits for her words (#234). While the picker hands
  /// it over she may have pressed the microphone; then it is not attached.
  private func picked(_ data: Data) {
    model.attachPicture(data)
  }

  /// A screenshot into the chat, as in the usual chat apps (the author chose this on 2026-11-07,
  /// #221). What she has written goes with it.
  private var photoButton: some View {
    Button {
      writing = false
      choosingPhoto = true
    } label: {
      Image(systemName: "photo")
        .font(.body.weight(.semibold))
        .dynamicTypeSize(...Self.largestButtonType)
        .foregroundStyle(model.voice.acceptsText ? Color.accentColor : Color.secondary)
        .frame(width: 34, height: 34)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(!model.voice.acceptsText)
    .accessibilityShowsLargeContentViewer { Label("スクショを見せる", systemImage: "photo") }
    .accessibilityLabel("スクショを見せる")
    .accessibilityHint(
      model.voice.acceptsText
        ? "写真の中からスクショを1枚選ぶと、欄に付きます。欄を長く押してペーストしても付けられます。何をしたいかを書くか話して送ると、みまもりが見て、押す場所に丸を付けて答えます。送った画像は小さくしてこの iPhone の会話にだけ残します"
        : "答えを待っています")
  }

  private var microphone: some View {
    Button {
      writing = false
      model.micTapped()
    } label: {
      Image(systemName: "mic.fill")
        .font(.body.weight(.semibold))
        .dynamicTypeSize(...Self.largestButtonType)
        .foregroundStyle(.white)
        .frame(width: 34, height: 34)
        .background(Circle().fill(Color.accentColor))
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .transition(.scale.combined(with: .opacity))
    .accessibilityShowsLargeContentViewer {
      Label(model.voice.micLabel, systemImage: "mic.fill")
    }
    .accessibilityLabel(model.voice.micLabel)
    .accessibilityHint(model.voice.micHint)
  }
}

/// "0:05" since listening started, ticking each second. "0:00" while the permission sheets are up.
private struct RecordingClockView: View {
  let since: Date?

  var body: some View {
    TimelineView(.periodic(from: since ?? .now, by: 1)) { context in
      let elapsed = since.map { context.date.timeIntervalSince($0) } ?? 0
      Text(RecordingClock.text(elapsed: elapsed))
        .font(.body)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityLabel(RecordingBar.clockLabel(elapsed: elapsed))
    }
  }
}

/// Dots that grow with her voice, newest on the right. Drawn from the microphone's loudness on the
/// iPhone only.
/// Reads `levels` itself, so their many updates a second redraw only the dots.
private struct VoiceLevelDots: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let values = model.levels.values
    GeometryReader { geometry in
      let spacing: CGFloat = 3
      let count = values.count
      let width = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
      HStack(spacing: spacing) {
        ForEach(values.indices, id: \.self) { i in
          Capsule()
            .fill(Color.primary.opacity(0.7))
            .frame(width: width, height: max(width, geometry.size.height * values[i]))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .animation(.linear(duration: 0.08), value: values)
    }
    .frame(height: 28)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(RecordingBar.levelsLabel)
  }
}

/// The screenshot she showed, under her line and then under the answer, with the ring where to press.
/// At most 420 points tall, so on an iPhone the answer above it and the field below stay in view.
/// The screenshot waiting on the field (#234): small, with a remove button on its corner. No words;
/// VoiceOver has them.
private struct AttachedPictureView: View {
  let picture: ConsultPicture
  let remove: () -> Void

  var body: some View {
    let size = picture.original
    Image(uiImage: picture.image)
      .resizable()
      .aspectRatio(CGFloat(size.width) / CGFloat(size.height), contentMode: .fit)
      .frame(height: 72)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator), lineWidth: 0.5))
      .accessibilityElement()
      .accessibilityLabel("付けたスクショ")
      .accessibilityHint("送るボタンを押すと、書いた言葉と一緒に送ります。言葉が無ければスクショだけを送ります")
      .overlay(alignment: .topTrailing) {
        Button(action: remove) {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.6))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 16, y: -16)
        .accessibilityLabel("スクショを外す")
        .accessibilityHint("付けたスクショを送らずに外します")
      }
      .padding(.top, 12)
      .padding(.trailing, 16)
  }
}

private struct ShownPictureView: View {
  let shown: ShownPicture

  var body: some View {
    let size = shown.picture.original
    CircledImage(image: shown.picture.image, original: size, circle: shown.circle)
      .aspectRatio(CGFloat(size.width) / CGFloat(size.height), contentMode: .fit)
      .frame(maxHeight: 420)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .frame(maxWidth: .infinity, alignment: .leading)
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
struct ChatTurn: View {
  let message: ChatMessage
  let time: ChatStamp?
  /// Reads the screenshot kept with her message (#243), once, when the turn appears.
  var loadPicture: (() -> Data?)? = nil
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var picture: UIImage?

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
    .task(id: message.picture) {
      guard message.picture != nil, let data = loadPicture?() else { return }
      picture = UIImage(data: data)
    }
  }

  /// Her words in a bubble, with the screenshot she showed small above it (#243). An image sent alone
  /// has no bubble.
  @ViewBuilder private var bubble: some View {
    VStack(alignment: .trailing, spacing: 4) {
      if message.picture != nil {
        ChatPictureThumbnail(image: picture)
      }
      if !message.text.isEmpty {
        Bubble(text: message.text, fill: Color(.secondarySystemBackground), foreground: .primary)
      }
    }
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

  /// "画像を見せました" stays here only: the screen shows the image instead (#243).
  private var label: String {
    let who = message.role == .protected ? "あなた" : "答え"
    let said = [message.picture != nil ? VoiceConsult.pictureLine : nil, message.text.isEmpty ? nil : message.text]
      .compactMap { $0 }
      .joined(separator: "、")
    guard let time else { return "\(who)、\(said)" }
    return "\(who)、\(said)、\(time.spoken)"
  }
}

/// The screenshot kept with her message, small, as in the usual chat apps (#243). A soft placeholder
/// while it is read, or when it could not be kept.
private struct ChatPictureThumbnail: View {
  let image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(image.size.width / max(image.size.height, 1), contentMode: .fit)
      } else {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.secondarySystemBackground))
          .aspectRatio(0.5, contentMode: .fit)
          .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
      }
    }
    .frame(height: 140)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 0.5))
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

struct Bubble: View {
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

/// `CallFollowUp.prompt` with one button that closes it. It asks nothing (#123), so the button is
/// not an answer; talking or writing to the AI is what the prompt invites.
struct FollowUpView: View {
  let prompt: String
  /// "わかった". Her screen closes the prompt; the judges' tour does the same in its own state.
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(prompt)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("電話で困ったことがあれば、マイクを押して話すか、下の欄に書いてください")
      Button("わかった") { onClose() }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .accessibilityHint("押すと、この声かけを閉じます。家族には何も知らせません")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
  }
}

/// "iPhoneの空きが残り0.8GB。一緒に空けよう" with "あとで" and "空ける" (#19). The same row as the
/// call follow-up, so her screen gets no new kind of control.
struct CheckupView: View {
  let prompt: String
  let onLater: () -> Void
  let onStart: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(prompt)
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("iPhone の空きが少なくなっています。空けると、写真やアプリの更新が入らなくなるのを防げます。広告の掃除アプリは入れなくて大丈夫です")
      HStack(spacing: 12) {
        Spacer()
        Button("あとで") { onLater() }
          .font(.subheadline)
          .buttonStyle(.bordered)
          .accessibilityHint("押すと、この声かけを1日出しません")
        Button("空ける") { onStart() }
          .font(.subheadline.weight(.semibold))
          .buttonStyle(.borderedProminent)
          .accessibilityHint("押すと、設定の iPhoneストレージ を開く手順を会話に出します")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
  }
}

/// The family notices in one strip: the most pressing one (`ProtectedNotice.mostPressing`), how many
/// there are, and a chevron. A tap opens every notice with what was passed to the family.
struct NoticeStrip: View {
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

struct NoticeRow: View {
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
