import SwiftUI

struct WebResearchSaveSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var reportID: UUID
  @State private var selected: UUID?
  @State private var newName = ""
  @State private var saving = false
  @State private var failure: String?
  var body: some View {
    NavigationStack {
      MemoraForm {
        Section("保存先") {
          Picker("プロジェクト", selection: $selected) {
            Text("新しいプロジェクト").tag(nil as UUID?)
            ForEach(model.spaces) { space in Text(space.name).tag(space.id as UUID?) }
          }
          if selected == nil { TextField("プロジェクト名", text: $newName) }
        }
        if let failure { Text(failure).foregroundStyle(.secondary) }
        Section {
          Button(saving ? "保存中" : "レポートとソースを保存") {
            saving = true
            Task { @MainActor in
              defer { saving = false }
              guard let projectID = selected ?? model.addSpace(name: newName) else { failure = "保存先を作成できませんでした。"; return }
              selected = projectID
              do {
                if try await model.saveWebResearch(reportID, to: projectID) { dismiss() }
                else { failure = "保存できませんでした。保存先と保存済み状態を確認してください。" }
              } catch { failure = "ファイルを保存できませんでした。調査結果は残っています。" }
            }
          }.disabled(saving || (selected == nil && newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        } footer: { Text("同じURLの既存ソースは再利用します。保存するのは取得済みの抜粋・抽出本文です。外部AIへの再送許可は自動で付けません。") }
      }
      .navigationTitle("プロジェクトにまとめる").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() }.disabled(saving) } }
      .interactiveDismissDisabled(saving)
    }
  }
}
