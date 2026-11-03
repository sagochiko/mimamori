import MimamoriCore
import SwiftUI

/// The family's screen: a card per case, newest first, then the invite.
struct FamilyHomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        ForEach(model.familyCards, id: \.item.id) { card in
          CaseCardView(card: card)
        }
        if model.familyCards.isEmpty { Spacer(minLength: 80) }
        InviteSection()
      }
      .padding(24)
    }
    .refreshable { await model.loadCases() }
    .task { await model.keepCasesFresh() }
  }
}

private struct InviteSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 24) {
      if let invite = model.invite {
        InviteCodeView(invite: invite)
      }
      Button {
        Task { await model.createInvite() }
      } label: {
        if model.isBusy { ProgressView().tint(.white) } else { Text("招待") }
      }
      .buttonStyle(BigButtonStyle(prominent: model.invite == nil && model.familyCards.isEmpty))
      .disabled(model.isBusy)
      .accessibilityLabel(model.invite == nil ? "招待のコードを出す" : "新しい招待のコードを出す")
      .accessibilityHint("見守られる人やほかの家族が、この6桁のコードで入ります。24時間使えます")
    }
  }
}

struct InviteCodeView: View {
  let invite: Invite

  private var spaced: String {
    let digits = Array(invite.code.value)
    return String(digits[0..<3]) + " " + String(digits[3...])
  }

  var body: some View {
    VStack(spacing: 12) {
      Text(spaced)
        .font(.system(size: 64, weight: .bold, design: .monospaced))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .textSelection(.enabled)
        // Read digit by digit, not as "four hundred eighty-two".
        .accessibilityLabel("招待のコード \(invite.code.value.map(String.init).joined(separator: " "))")
        .accessibilityHint("見守られる人やほかの家族のスマホで、この6桁を入れます")
      Text(invite.expiresAt, format: .dateTime.month().day().hour().minute())
        .font(.title3)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(invite.expiresAt.formatted(.dateTime.month().day().hour().minute()))まで使えます")
      ShareLink(item: invite.code.value) {
        Text("送る")
      }
      .buttonStyle(BigButtonStyle(prominent: false))
      .accessibilityLabel("コードを送る")
      .accessibilityHint("メッセージなどで招待のコードを送ります")
    }
  }
}
