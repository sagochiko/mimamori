import MimamoriCore
import SwiftUI

/// The family's screen: the morning smiles first, then a card per case, newest first, then the invite.
struct FamilyHomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        SmileSection()
        ForEach(model.familyCards, id: \.item.id) { card in
          CaseCardView(card: card)
        }
        if model.familyCards.isEmpty { Spacer(minLength: 80) }
        InviteSection()
      }
      .padding(24)
    }
    .refreshable {
      await model.loadCases()
      await model.loadSmiles()
    }
    .task { await model.keepCasesFresh() }
  }
}

/// Today's smile of the protected member, large, the two ways to answer, everyone's smiles, and the
/// hour by which her smile is expected (after it, with no smile that day, the family is told quietly).
private struct SmileSection: View {
  @Environment(AppModel.self) private var model
  @State private var camera = false
  @State private var writing = false

  var body: some View {
    VStack(spacing: 16) {
      if let today = model.smileBoard.todaysProtectedSmile(now: model.now) {
        VStack(spacing: 8) {
          SmilePhoto(smile: today)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 280)
            .clipShape(RoundedRectangle(cornerRadius: 28))
          Text(today.displayName).font(.title3.bold())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日の\(today.spokenLabel)")
      }
      HStack(spacing: 12) {
        Button("笑顔") { camera = true }
          .buttonStyle(BigButtonStyle())
          .accessibilityLabel("笑顔で返す")
          .accessibilityHint("前のカメラに向かって笑うと、その場で撮って家族みんなに送ります")
        Button("ひと言") { writing = true }
          .buttonStyle(BigButtonStyle(prominent: false))
          .accessibilityLabel("ひと言で返す")
          .accessibilityHint("写真なしで、「おはよう」などの決まった言葉から選んで家族みんなに送ります")
      }
      if !model.smileBoard.smiles.isEmpty {
        SmileStrip()
      }
      DeadlineMenu()
    }
    .fullScreenCover(isPresented: $camera) { SmileCaptureView() }
    .sheet(isPresented: $writing) {
      // Full height, and a swipe scrolls the words before it moves the sheet: at the medium height the
      // fifth word was cut off, and at the largest text size a swipe could not reach it.
      NoteSheet()
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
    }
    .onAppear {
      #if DEBUG
        if ScreenshotStubTransport.cameraOpen { camera = true }
        if ScreenshotStubTransport.noteOpen { writing = true }
      #endif
    }
  }
}

/// The hour (JST) by which her smile is expected. Only the number shows; what it means is read aloud.
private struct DeadlineMenu: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let hour = model.smileBoard.deadlineHour
    Menu {
      Picker("時刻", selection: Binding(get: { hour }, set: { new in Task { await model.setSmileDeadline(new) } })) {
        ForEach(Array(SmileBoard.deadlineHours), id: \.self) { Text("\($0)時").tag($0) }
      }
    } label: {
      Label("\(hour)時", systemImage: "bell")
        .font(.headline)
        .foregroundStyle(.secondary)
    }
    .accessibilityLabel("見守られる人の笑顔を待つ時刻、\(hour)時")
    .accessibilityHint("この時刻までにその日の笑顔が届かなければ、家族にそっと知らせます。押すと時刻を変えられます")
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
