import MimamoriCore
import SwiftUI

/// One case on a family member's screen: the level, the one line of what she is troubled by, what
/// the AI told her, whether it was solved, and "電話する" and "解決". Every family member sees the same
/// card. The reasons, and what the research in the background found (task 11), are read by VoiceOver
/// only (docs/design.md, "家族の画面"). "解決" asks first in an alert titled with the card's
/// one line, with "解決にする" and "やめる" and no sentence of its own (#60).
struct CaseCardView: View {
  let card: FamilyCard
  /// "解決にする". Nil sends `POST /cases/{id}/resolve`; the judges' tour resolves in its own state.
  var onResolve: ((Case) -> Void)? = nil
  /// The card whose "電話する" and "解決" get the balloons (`OnboardingGuide`).
  var guides = false
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  @State private var askingNumber = false
  @State private var confirmation = ResolveConfirmation()

  private var item: Case { card.item }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if let alert = item.alert {
        Text(alert.summary)
          .font(.title3.bold())
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel(summaryLabel(alert))
          .accessibilityHint(evidenceHint(alert))
        // The summary from fixed choices (#271), the server's own line; nothing when there is none.
        if let digest = alert.digest {
          Text(digest)
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("話題と次にすること、\(digest.replacingOccurrences(of: " / ", with: "、"))")
        }
      }
      if let reply = item.aiReply {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text("AI").font(.caption.bold()).foregroundStyle(.secondary)
          Text(reply).lineLimit(2)
        }
        .font(.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI が母に答えたこと、\(reply)")
      }
      Text(card.status)
        .font(.headline)
        .foregroundStyle(item.state == .resolved ? Color.secondary : Color.accentColor)
        .accessibilityHint(statusHint)
      if !actions.isEmpty { buttons }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(levelColor.opacity(0.6), lineWidth: 2))
    // An alert, not a confirmation dialog: on iOS 26 the dialog is a popover over the next card that
    // drops the cancel button, and both "解決にする" and "やめる" must be shown. No message line.
    .alert(
      ResolveConfirmation.title(for: item),
      isPresented: Binding(
        get: { confirmation.asking?.id == item.id },
        set: { shown in if !shown { _ = confirmation.choose(.cancel) } }
      )
    ) {
      ForEach(ResolveChoice.allCases, id: \.self) { choice in
        Button(choice.title, role: choice == .cancel ? .cancel : nil) {
          if let chosen = confirmation.choose(choice) {
            if let onResolve { onResolve(chosen) } else { Task { await model.resolve(chosen) } }
          }
        }
        .accessibilityHint(choice.hint)
      }
    }
    .sheet(isPresented: $askingNumber) {
      PhoneNumberSheet { number in
        ProtectedPhoneStore.save(number)
        openURL(number.url)
      }
    }
  }

  private func summaryLabel(_ alert: CaseAlert) -> String {
    let reasons = alert.reasons.isEmpty ? "" : "。理由、\(alert.reasons.joined(separator: "、"))"
    let evidence =
      alert.evidence.isEmpty
      ? "" : "。出典、\(alert.evidence.map(\.text).joined(separator: "、"))"
    return "困りごと、\(alert.summary)\(reasons)\(evidence)"
  }

  /// Where the evidence was read, by site name, so it can be looked up; nothing on screen.
  private func evidenceHint(_ alert: CaseAlert) -> String {
    let hosts = alert.evidence.compactMap { $0.url.host() }
    return hosts.isEmpty ? "" : "出典、\(hosts.joined(separator: "、"))"
  }

  private var statusHint: String {
    item.state == .resolved
      ? "母と話して解決したと、家族の誰かが押しました"
      : "家族の誰かが母と話して解決を押すまで、このままです"
  }

  private var header: some View {
    HStack {
      if let level = item.alert?.level {
        Text(level.familyBadge)
          .font(.headline)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(Capsule().fill(levelColor.opacity(0.2)))
          .foregroundStyle(levelColor)
          .accessibilityLabel("\(level.familyBadge)、\(level.meaning)")
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

  /// The judges' tour (`onResolve` set) has no mother to call, so "電話する" is left out there; asking
  /// for 母の電話番号 would keep whatever a judge typed on this iPhone.
  private var actions: [CardAction] {
    onResolve == nil ? card.actions : card.actions.filter { $0 != .call }
  }

  private var buttons: some View {
    HStack(spacing: 10) {
      ForEach(actions, id: \.self) { action in
        Button {
          perform(action)
        } label: {
          Text(action.title)
        }
        .buttonStyle(CardButtonStyle(prominent: action == .call))
        .disabled(model.isBusy)
        .accessibilityHint(action.hint)
        .guideTarget(guides ? (action == .call ? .call : .resolve) : nil)
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
    case .resolve: confirmation.ask(item)
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
    case .call: "母に電話します。長押しで番号を変えられます"
    case .resolve: "母と話して解決したら押します。押すと確かめます"
    }
  }
}

extension ResolveChoice {
  /// What the choice does, said only by VoiceOver.
  var hint: String {
    switch self {
    case .resolve: "この相談を解決にして、ほかの家族にも解決と知らせます。母の画面からこの相談が消えます"
    case .cancel: "解決にせず、カードに戻ります。誰にも知らせません"
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

/// Smaller than `BigButtonStyle`, so two buttons fit side by side on a card.
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

/// The protected person's phone number for "電話する", entered on a family member's iPhone.
/// Kept only on this device; never sent to the server.
enum ProtectedPhoneStore {
  private static let key = "mimamori.protectedPhone"

  static func load() -> PhoneNumber? {
    UserDefaults.standard.string(forKey: key).flatMap(PhoneNumber.init)
  }

  static func save(_ number: PhoneNumber) {
    UserDefaults.standard.set(number.digits, forKey: key)
  }
}
