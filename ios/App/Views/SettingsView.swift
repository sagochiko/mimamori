import MimamoriCore
import SwiftUI

/// Her settings inside the app (#222): the daily prompt, its hour, and reading answers aloud. The
/// same keys as Settings > みまもり (`Settings.bundle`), read and written through Core, so a change in
/// either shows in the other. Opened from the menu at the end of her smile row (`WipeMenu`). Only
/// the names stay on screen; what each one does is read aloud.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var daily = DailyCheckInNotifier.settings
  @State private var readAloud = ReadAloudSettings(reading: {
    UserDefaults.standard.object(forKey: $0)
  })

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle(DailyCheckInSettings.title, isOn: $daily.isOn)
            .accessibilityHint("オンにすると、毎日決まった時刻に、知らない人から電話や連絡があったかを通知で聞きます")
          Picker(DailyCheckInSettings.hourTitle, selection: $daily.hour) {
            ForEach(DailyCheckInSettings.hours, id: \.self) { hour in
              Text(DailyCheckInSettings.label(for: hour)).tag(hour)
            }
          }
          .disabled(!daily.isOn)
          .accessibilityHint("毎日の声かけの通知を出す時刻です")
        }
        Section {
          Toggle(ReadAloudSettings.title, isOn: $readAloud.isOn)
            .accessibilityHint("オンにすると、声で聞いたときだけ答えを声で読みます。文字で聞いたときは読みません")
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
    // Settings may have changed while the app was away; show what is stored now.
    .onAppear {
      daily = DailyCheckInNotifier.settings
      readAloud = ReadAloudSettings(reading: { UserDefaults.standard.object(forKey: $0) })
    }
    .onChange(of: daily) { _, new in
      write(new.stored)
      model.settingsChanged()
    }
    .onChange(of: readAloud) { _, new in write(new.stored) }
  }

  private func write(_ values: [String: Any]) {
    for (key, value) in values { UserDefaults.standard.set(value, forKey: key) }
  }
}
