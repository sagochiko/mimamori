import MimamoriCore
import SwiftUI

/// One case on a family member's screen: level, what arrived, what the AI told the mother,
/// the replies, who has it, and the buttons from `FamilyCard`.
struct CaseCardView: View {
  let card: FamilyCard
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var composing = false
  @State private var askingNumber = false

  private var item: Case { card.item }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      if let alert = item.alert {
        Text(alert.summary)
          .font(.title3.bold())
          .accessibilityLabel("届いたもの、\(alert.summary)")
        ForEach(alert.reasons, id: \.self) { reason in
          Text(reason)
            .font(.body)
            .foregroundStyle(.secondary)
            .accessibilityLabel("理由、\(reason)")
        }
      }
      if let reply = item.aiReply {
        Label {
          Text(reply)
        } icon: {
          Text("AI").font(.caption.bold())
        }
        .font(.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI が母に答えたこと、\(reply)")
      }
      ForEach(item.relays) { relay in
        VStack(alignment: .leading, spacing: 2) {
          Text("\(relay.fromName)から").font(.subheadline.bold())
          Text(relay.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("母に届けた返事です")
      }
      if let status = card.status {
        Text(status)
          .font(.headline)
          .foregroundStyle(item.state == .resolved ? Color.secondary : Color.accentColor)
      }
      buttons
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(levelColor.opacity(0.6), lineWidth: 2))
    .sheet(isPresented: $composing) {
      RelayComposer(item: item)
    }
    .sheet(isPresented: $askingNumber) {
      PhoneNumberSheet { number in
        ProtectedPhoneStore.save(number)
        openURL(number.url)
      }
    }
  }

  private var header: some View {
    HStack {
      if let level = item.alert?.level {
        Text("\(level.rawValue)段階")
          .font(.headline)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Capsule().fill(levelColor.opacity(0.2)))
          .foregroundStyle(levelColor)
          .accessibilityLabel("危なさ\(level.rawValue)段階、\(level.meaning)")
      }
      Spacer()
      Text(item.notifiedAt, format: .dateTime.hour().minute())
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(item.notifiedAt.formatted(.dateTime.hour().minute()))に届きました")
    }
  }

  private var levelColor: Color {
    switch item.alert?.level {
    case .doNotOpen: .red
    case .waitForFamily: .orange
    default: .gray
    }
  }

  private var buttons: some View {
    VStack(spacing: 10) {
      ForEach(card.actions, id: \.self) { action in
        Button {
          perform(action)
        } label: {
          Text(action.title)
        }
        .buttonStyle(CardButtonStyle(prominent: action == .accept || action == .reply))
        .disabled(model.isBusy)
        .accessibilityHint(action.hint)
        .contextMenu {
          if action == .call {
            Button("番号を変える") { askingNumber = true }
          }
        }
      }
    }
  }

  private func perform(_ action: CardAction) {
    switch action {
    case .accept: Task { await model.accept(item) }
    case .reply: composing = true
    case .resolve: Task { await model.resolve(item) }
    case .call:
      if let number = ProtectedPhoneStore.load() {
        openURL(number.url)
      } else {
        askingNumber = true
      }
    }
  }
}

extension CardAction {
  /// The explanations that are not on screen.
  var hint: String {
    switch self {
    case .accept: "最初に押した人が受け持ちます。ほかの家族には対応中と出て、母のAIの案内は止まります"
    case .reply: "書いた文を母のiPhoneに届け、読み上げます"
    case .call: "母に電話します。長押しで番号を変えられます"
    case .resolve: "この相談を解決にします"
    }
  }
}

extension Level {
  var meaning: String {
    switch self {
    case .doNotOpen: "開かないで"
    case .waitForFamily: "家族に確かめるまで待って"
    case .lowConcern: "心配は少ないけど、お金や暗証番号を聞かれたら止めて"
    }
  }
}

/// Smaller than `BigButtonStyle`, so three buttons fit on a card.
struct CardButtonStyle: ButtonStyle {
  var prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .frame(maxWidth: .infinity, minHeight: 52)
      .foregroundStyle(prominent ? Color.white : Color.accentColor)
      .background(
        RoundedRectangle(cornerRadius: 14).fill(
          prominent ? Color.accentColor : Color.accentColor.opacity(0.15))
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

/// "母に返事する": one message, sent as text and read aloud on the mother's iPhone.
struct RelayComposer: View {
  let item: Case
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var failure: Problem?
  @FocusState private var focused: Bool

  private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
  private let limit = 200

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        TextField("返事", text: $text, axis: .vertical)
          .font(.title3)
          .lineLimit(4...8)
          .focused($focused)
          .padding(14)
          .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
          .accessibilityLabel("母への返事")
          .accessibilityHint("書いた文は母のiPhoneで、ふつうの声で読み上げます。\(limit)文字まで")
        HStack {
          Spacer()
          Text("\(trimmed.count)/\(limit)")
            .font(.footnote)
            .foregroundStyle(trimmed.count > limit ? Color.red : Color.secondary)
            .accessibilityLabel("\(trimmed.count)文字、\(limit)文字まで")
        }
        Button {
          Task {
            // On failure the sheet stays open with the text, so the reply can be sent again.
            failure = await model.relay(item, text: trimmed)
            if failure == nil { dismiss() }
          }
        } label: {
          if model.isBusy { ProgressView().tint(.white) } else { Text("送る") }
        }
        .buttonStyle(BigButtonStyle())
        .disabled(trimmed.isEmpty || trimmed.count > limit || model.isBusy)
        .accessibilityHint("母に届けます")
        Spacer()
      }
      .padding(24)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("やめる") { dismiss() }
        }
      }
    }
    .onAppear { focused = true }
    .alert(
      failure.map(\.title) ?? "",
      isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button("OK", role: .cancel) {}
    }
  }
}

/// Asked once, the first time "電話する" is pressed. The number stays on this iPhone.
struct PhoneNumberSheet: View {
  let onSave: (PhoneNumber) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var text = ProtectedPhoneStore.load()?.digits ?? ""

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        TextField("電話番号", text: $text)
          .keyboardType(.phonePad)
          .textContentType(.telephoneNumber)
          .font(.title2)
          .padding(14)
          .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
          .accessibilityLabel("母の電話番号")
          .accessibilityHint("このiPhoneにだけ残し、どこにも送りません")
        Button("保存") {
          guard let number = PhoneNumber(text) else { return }
          dismiss()
          onSave(number)
        }
        .buttonStyle(BigButtonStyle())
        .disabled(PhoneNumber(text) == nil)
        .accessibilityHint("保存して電話をかけます")
        Spacer()
      }
      .padding(24)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("やめる") { dismiss() }
        }
      }
    }
  }
}
