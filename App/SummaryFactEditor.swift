import SwiftUI

struct SummaryFactEditor: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  var versionID: UUID
  var original: SummaryKnowledge.Fact?
  @State private var content: String
  @State private var category: SummaryKnowledge.Category
  @State private var status: SummaryKnowledge.Status
  @State private var context: LocalImportContext?
  @State private var cancelsEditing = false
  @State private var completed = false
  @State private var failure = false

  init(meetingID: UUID, versionID: UUID, original: SummaryKnowledge.Fact? = nil) {
    self.meetingID = meetingID; self.versionID = versionID; self.original = original
    _content = State(initialValue: original?.content ?? "")
    _category = State(initialValue: original?.category ?? .keyFact)
    _status = State(initialValue: original?.status ?? .confirmed)
  }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextField("内容", text: $content, axis: .vertical).lineLimit(3...12)
            .accessibilityIdentifier("summary.fact.content")
          Picker("情報の種類", selection: $category) {
            ForEach(SummaryKnowledge.Category.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          Picker("原文での状態", selection: $status) {
            ForEach(SummaryKnowledge.Status.allCases, id: \.self) { Text($0.label).tag($0) }
          }
        } footer: {
          Text("本人の編集として履歴に残します。本文・文字起こし・タスクは変更しません。生成時の引用は、この編集の根拠として引き継ぎません。")
        }
        if failure { Text("記録が更新されたか、保存できませんでした。書きかけを保持しているので、開き直して確認してください。") }
      }
      .navigationTitle(original == nil ? "抽出情報を追加" : "抽出情報を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("キャンセル", icon: .xmark) { cancelsEditing = true }
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) {
            guard context?.isCurrent(in: model) == true,
              model.saveSummaryFact(meetingID: meetingID, versionID: versionID, original: original,
                category: category, content: content, status: status) else { failure = true; return }
            completed = true
            dismiss()
          }
          .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.count > 4_000)
          .accessibilityIdentifier("summary.fact.save")
        }
      }
      .onAppear { if context == nil { context = LocalImportContext(in: model) } }
    }
    .protectsEditorDraft(key: "editor.\(model.currentTeamID ?? "personal").summary-fact.\(meetingID).\(original?.id ?? "new")",
      fields: [EditorDraftField("content", $content), EditorDraftField("category", $category), EditorDraftField("status", $status)],
      cancels: $cancelsEditing, completed: completed)
  }
}
