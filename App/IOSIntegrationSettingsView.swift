import AppIntents
import SwiftUI

struct IOSIntegrationSettingsView: View {
  @Environment(MemoraModel.self) private var model
  @AppStorage("memora.widgets.enabled") private var sharesCounts = false
  @AppStorage("memora.widgets.projectNames") private var sharesProjectNames = false
  @AppStorage("memora.widgets.calendarTime") private var sharesCalendarTime = false
  @AppStorage("memora.shortcuts.projectNames") private var shortcutProjectNames = false

  var body: some View {
    Form {
      Section("ウィジェット") {
        Text("ホーム画面を長押し → 編集 → ウィジェットを追加 → Memora")
          .font(.subheadline).foregroundStyle(.secondary)
        if MemoraWidgetSnapshotStore.fileURL == nil {
          Text("Ask AIとクイック記録を使えます。今日・プロジェクトの情報共有は、このビルドでは未設定です。")
        }
        Toggle("件数を表示", isOn: $sharesCounts).disabled(MemoraWidgetSnapshotStore.fileURL == nil)
        Toggle("プロジェクト名を表示", isOn: $sharesProjectNames).disabled(!sharesCounts || MemoraWidgetSnapshotStore.fileURL == nil)
        Toggle("次の予定の時刻を表示", isOn: $sharesCalendarTime).disabled(!sharesCounts || MemoraWidgetSnapshotStore.fileURL == nil)
      }
      Section("ショートカット") {
        Toggle("プロジェクト名を候補に表示", isOn: $shortcutProjectNames)
        Text("プロジェクト名だけをSiriとショートカットに表示します。記録の内容は渡しません。Face IDロックが有効な間は候補を出しません。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        Text("コントロールの「Memoraを開く」はアプリを開きます。録音開始はクイック記録や「Memoraで録音を開始」のショートカットから行います。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("ウィジェットとショートカット").navigationBarTitleDisplayMode(.inline)
    .onChange(of: sharesCounts) { _, _ in model.scheduleWidgetSnapshot() }
    .onChange(of: sharesProjectNames) { _, _ in model.scheduleWidgetSnapshot() }
    .onChange(of: sharesCalendarTime) { _, _ in model.scheduleWidgetSnapshot() }
    .onChange(of: shortcutProjectNames) { _, _ in MemoraAppShortcuts.updateAppShortcutParameters() }
  }
}
