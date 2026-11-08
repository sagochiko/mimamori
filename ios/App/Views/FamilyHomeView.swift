import MimamoriCore
import SwiftUI

/// The family's screen. Until the protected member joins, only "招待" in the middle (#244); after, her
/// smile today on top, a card per case, newest first, then everyone's smiles and the hour her smile is
/// expected by, with "笑顔" and "招待" as small buttons at the top right next to the menu.
struct FamilyHomeView: View {
  @Environment(AppModel.self) private var model
  @State private var camera = false
  @State private var inviting = false
  @Environment(OnboardingGuide.self) private var guide: OnboardingGuide?

  var body: some View {
    ScrollViewReader { scroller in
      home
        // A card's buttons may sit below the screen: bring them in before their balloon (#285).
        // scrollTo finds the card's row in the List by its id.
        .onChange(of: guide?.tour?.current) { _, step in
          guard step == .call || step == .resolve, let id = model.guidedCardID else { return }
          withAnimation { scroller.scrollTo(id, anchor: .bottom) }
        }
    }
  }

  private var home: some View {
    Group {
      if model.protectedJoined {
        // A List, not a ScrollView: swipeActions on a card (#280) only work on the rows of a List.
        JoinedSection()
      } else {
        ScrollView {
          WaitingSection()
            .containerRelativeFrame(.vertical)
        }
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
            .guideTarget(.familySmile)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("招待") { inviting = true }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("ほかの家族を招待する")
            .accessibilityHint("6桁の招待のコードを出します。ほかの家族がこのコードで入ります。24時間使えます")
            .guideTarget(.invite)
        }
      }
      ToolbarItem(placement: .topBarTrailing) { WipeMenu().guideTarget(.settings) }
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
        Button("戻る") { model.showJoinedHome() }
          .font(.body)
          .accessibilityInputLabels(["戻る", "家族の画面へ"])
          .accessibilityHint("見守られる人の笑顔と知らせが並ぶ家族の画面に移ります。招待は右上からまた出せます")
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

/// After she joined: her smile today, the cards, everyone's smiles, and the hour. Each is a row of a
/// plain List drawn without separators or row backgrounds, so it looks as the stack it was; a List is
/// what lets a resolved card be swiped to "消す" (#280).
private struct JoinedSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      if let today = model.smileBoard.todaysProtectedSmile(now: model.now) {
        VStack(spacing: 8) {
          SmilePhoto(smile: today)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 280)
            .clipShape(RoundedRectangle(cornerRadius: 28))
          Text(today.displayName).font(.title3.bold())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日の\(today.spokenLabel)")
        .homeRow(top: 24)
      }
      // The swipe's "消す" is also a VoiceOver action of the card: List lists swipe actions
      // there itself, so a second accessibilityAction would read it twice (verifier, PR #284).
      ForEach(model.familyCards, id: \.item.id) { card in
        // The balloons point at the buttons of the newest card that has them only.
        CaseCardView(card: card, guides: card.item.id == model.guidedCardID)
          .homeRow()
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if card.removable {
              Button(FamilyCard.removeTitle, role: .destructive) {
                Task { await model.remove(card.item) }
              }
            }
          }
          .id(card.item.id)
      }
      if !model.smileBoard.photos.isEmpty {
        SmileStrip()
          .homeRow()
      }
      DeadlineMenu()
        .frame(maxWidth: .infinity)
        .homeRow(bottom: 24)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }
}

extension View {
  /// A row of the family's home drawn as part of a stack: 24 at the sides, 20 between rows, no
  /// separator and no row background.
  fileprivate func homeRow(top: CGFloat = 10, bottom: CGFloat = 10) -> some View {
    listRowInsets(EdgeInsets(top: top, leading: 24, bottom: bottom, trailing: 24))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
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
      } else if model.isBusy {
        ProgressView()
      } else {
        // A failed request leaves no code; this asks again (review 1 of PR #246).
        NewCodeButton()
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
      // "まで": a bare time under the code read as nothing in particular to the author (#279).
      Text("\(InviteMessage.expiry(invite.expiresAt))まで")
        .font(.title3)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(InviteMessage.expiry(invite.expiresAt))まで使えます")
      // The link to the app and the steps go with the code (#279); see `InviteMessage`.
      ShareLink(item: InviteMessage.text(for: invite)) {
        Text("送る")
      }
      .buttonStyle(BigButtonStyle())
      .accessibilityLabel("コードを送る")
      .accessibilityHint("アプリのリンク、入り方、招待のコードと期限をメッセージなどで送ります")
    }
  }
}

extension AppModel {
  /// The card whose "電話する" and "解決" get the balloons: the newest that still has them.
  var guidedCardID: Case.ID? {
    familyCards.first { !$0.actions.isEmpty }?.item.id
  }
}
