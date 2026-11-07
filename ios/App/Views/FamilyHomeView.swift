import MimamoriCore
import SwiftUI

/// The family's screen. Until the protected member joins, only "招待" in the middle (#244); after, her
/// smile today on top, a card per case, newest first, then everyone's smiles and the hour her smile is
/// expected by, with "笑顔" and "招待" as small buttons at the top right next to the menu.
struct FamilyHomeView: View {
  @Environment(AppModel.self) private var model
  @State private var camera = false
  @State private var inviting = false

  var body: some View {
    ScrollView {
      if model.protectedJoined {
        JoinedSection()
      } else {
        WaitingSection()
          .containerRelativeFrame(.vertical)
      }
    }
    .refreshable {
      await model.loadCases()
      await model.loadSmiles()
    }
    .task { await model.keepCasesFresh() }
    .toolbar {
      if model.protectedJoined {
        ToolbarItem(placement: .topBarTrailing) {
          Button("笑顔") { camera = true }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("笑顔で返す")
            .accessibilityHint("前のカメラに向かって笑うと、その場で撮って家族みんなに送ります")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("招待") { inviting = true }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("ほかの家族を招待する")
            .accessibilityHint("6桁の招待のコードを出します。ほかの家族がこのコードで入ります。24時間使えます")
        }
      }
      ToolbarItem(placement: .topBarTrailing) { WipeMenu() }
    }
    .fullScreenCover(isPresented: $camera) { SmileCaptureView() }
    .sheet(isPresented: $inviting) {
      InviteSheet()
        .presentationDetents([.medium])
    }
    .onAppear {
      #if DEBUG
        if ScreenshotStubTransport.cameraOpen { camera = true }
      #endif
    }
    .onChange(of: model.protectedJoined, initial: true) { _, joined in
      #if DEBUG
        // The stub's smiles and cases arrive after the screen appears.
        if ScreenshotStubTransport.inviteOpen, joined { inviting = true }
      #endif
    }
  }
}

/// Before she joins: one "招待" in the middle. Once pressed, the code large with "送る" under it, and
/// a small button for a new code.
private struct WaitingSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 24) {
      if let invite = model.invite {
        InviteCodeView(invite: invite)
        NewCodeButton()
      } else {
        Button {
          Task { await model.createInvite() }
        } label: {
          if model.isBusy { ProgressView().tint(.white) } else { Text("招待") }
        }
        .buttonStyle(BigButtonStyle())
        .disabled(model.isBusy)
        .accessibilityLabel("見守られる人を招待する")
        .accessibilityHint("6桁の招待のコードを出します。見守られる人がこのコードで入ると、ここに笑顔と知らせが並びます。24時間使えます")
      }
    }
    .padding(24)
    .onAppear {
      #if DEBUG
        if ScreenshotStubTransport.inviteOpen, model.invite == nil { Task { await model.createInvite() } }
      #endif
    }
  }
}

/// After she joined: her smile today, the cards, everyone's smiles, and the hour.
private struct JoinedSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 20) {
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
      ForEach(model.familyCards, id: \.item.id) { card in
        CaseCardView(card: card)
      }
      if !model.smileBoard.photos.isEmpty {
        SmileStrip()
      }
      DeadlineMenu()
    }
    .padding(24)
  }
}

/// "招待" at the top right after she joined: a code for another family member, made when it opens.
private struct InviteSheet: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: 24) {
      if let invite = model.invite {
        InviteCodeView(invite: invite)
        NewCodeButton()
      } else {
        ProgressView()
      }
    }
    .padding(24)
    .task { if model.invite == nil { await model.createInvite() } }
  }
}

/// A small button for a new code. The old one stays usable until it expires.
private struct NewCodeButton: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Button {
      Task { await model.createInvite() }
    } label: {
      if model.isBusy { ProgressView() } else { Image(systemName: "arrow.clockwise") }
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.circle)
    .disabled(model.isBusy)
    .accessibilityLabel("新しい招待のコードを出す")
    .accessibilityHint("今のコードとは別の6桁のコードを出します。24時間使えます")
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
      .buttonStyle(BigButtonStyle())
      .accessibilityLabel("コードを送る")
      .accessibilityHint("メッセージなどで招待のコードを送ります")
    }
  }
}
