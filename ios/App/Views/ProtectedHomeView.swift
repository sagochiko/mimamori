import MimamoriCore
import SwiftUI

/// The protected person's screen: what the family was told and their replies, then one big
/// microphone. Replies are read aloud once when they arrive; tapping one reads it again.
/// The microphone starts working in task 12. Explanations live in VoiceOver only.
struct ProtectedHomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let notices = model.protectedNotices
    VStack(spacing: 20) {
      if notices.isEmpty {
        Spacer()
        microphone
        Spacer()
      } else {
        // Scrolls instead of shortening a line: every word of a family reply must be readable.
        ScrollView {
          VStack(spacing: 16) {
            ForEach(notices) { notice in
              NoticeView(notice: notice)
            }
          }
        }
        .scrollBounceBehavior(.basedOnSize)
        microphone
      }
    }
    .padding(24)
    .task { await model.keepCasesFresh() }
  }

  private var microphone: some View {
    Button {
      // Task 12: start listening.
    } label: {
      Image(systemName: "mic.fill")
        .font(.system(size: 88, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 200, height: 200)
        .background(Circle().fill(Color.accentColor))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("話しかける")
    .accessibilityHint("準備中です。もうすぐ、押して話すとスマホの困りごとに答えます")
  }
}

private struct NoticeView: View {
  let notice: ProtectedNotice
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let status = notice.status {
        Text(status)
          .font(.title2.bold())
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityHint(hint(for: status))
      }
      if let summary = notice.summary {
        Text(summary)
          .font(.title3)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel("家族に伝えたこと、\(summary)")
      }
      if let reply = notice.reply {
        Button {
          model.speakAgain(reply)
        } label: {
          VStack(alignment: .leading, spacing: 6) {
            Text(reply.from).font(.title3.bold())
            Text(reply.body).font(.title2).fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .background(RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("家族が書いた返事です。押すともう一度読み上げます")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
  }

  private func hint(for status: String) -> String {
    switch status {
    case ProtectedNotice.toldFamily: "さっきの相談を家族に知らせました。家族が見たら、ここに名前が出ます"
    case ProtectedNotice.noReplyYet: "30分たっても家族が引き受けていません。急ぐときは家族に電話してください"
    default: "家族がこの相談を引き受けました。返事を待ってください"
    }
  }
}
