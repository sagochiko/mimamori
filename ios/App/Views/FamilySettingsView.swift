import MimamoriCore
import SwiftUI

/// The family member's settings (#282), in the same form as hers (`SettingsView`): whether a smile
/// from the family is told, and whether her missing smile is told, with the hour it is told after.
/// Opened from the menu at the top right of the family's screen (`WipeMenu`). The switches are this
/// member's own; the hour is one for the whole family. Notices of danger, the watch's self-check, and
/// joins have no switch. Only the names stay on screen; what each one does is read aloud.
struct FamilySettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let settings = model.memberSettings
    NavigationStack {
      Form {
        Section {
          Toggle(
            "笑顔が届いたとき",
            isOn: Binding(
              get: { settings.smileNotify },
              set: { on in update { $0.smileNotify = on } })
          )
          .accessibilityHint("オンにすると、家族の誰かが笑顔を送ったときに、音を鳴らさない通知で知らせます")
        }
        Section {
          Toggle(
            "笑顔が届かないとき",
            isOn: Binding(
              get: { settings.smileMissedNotify },
              set: { on in update { $0.smileMissedNotify = on } })
          )
          .accessibilityHint("オンにすると、下の時刻までに見守られる人のその日の笑顔が届かなければ、1日1回そっと知らせます")
          Picker(
            "時刻",
            selection: Binding(
              get: { model.smileBoard.deadlineHour },
              set: { new in Task { await model.setSmileDeadline(new) } })
          ) {
            ForEach(Array(SmileBoard.deadlineHours), id: \.self) { Text("\($0)時").tag($0) }
          }
          .disabled(!settings.smileMissedNotify)
          .accessibilityLabel("笑顔を待つ時刻、\(model.smileBoard.deadlineHour)時")
          .accessibilityHint("見守られる人の笑顔をこの時刻まで待ちます。家族みんなで1つの時刻です")
        }
      }
      .navigationTitle("設定")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("閉じる") { dismiss() }
        }
      }
    }
    .task { await model.loadMemberSettings() }
  }

  private func update(_ change: (inout MemberSettings) -> Void) {
    var next = model.memberSettings
    change(&next)
    Task { await model.setMemberSettings(next) }
  }
}
