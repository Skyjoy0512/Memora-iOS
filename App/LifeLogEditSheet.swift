import SwiftUI

/// Corrects a journal entry's title, text, and time. Changing the time moves the
/// entry to that day in the journal.
struct LifeLogEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var entry: LifeLogEntry
  @State private var title: String
  @State private var summary: String
  @State private var createdAt: Date

  init(entry: LifeLogEntry) {
    self.entry = entry
    _title = State(initialValue: entry.title)
    _summary = State(initialValue: entry.summary)
    _createdAt = State(initialValue: entry.createdAt)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("内容") {
          TextField("タイトル", text: $title, axis: .vertical)
          TextField("本文", text: $summary, axis: .vertical)
            .lineLimit(3...8)
        }

        Section {
          DatePicker("日時", selection: $createdAt)
        } header: {
          Text("日時")
        } footer: {
          Text("日時を変えると、ジャーナルのその日の位置へ移動します。")
        }
      }
      .navigationTitle("記録を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            model.updateLifeLogEntry(
              entry.id,
              title: title,
              summary: summary,
              createdAt: createdAt
            )
            dismiss()
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}
