import SwiftUI

struct RecordAIEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var request: RecordAIEdit
  var onSave: () -> Void

  @State private var proposal: String?
  @State private var status: String?
  @State private var isGenerating = true

  var body: some View {
    NavigationStack {
      Form {
        if isGenerating {
          ProgressView("変更案を作成中…")
        }
        if let status {
          Text(status).foregroundStyle(.secondary)
        }
        if let proposal {
          Section(request.field.title) {
            if !request.original.isEmpty {
              DisclosureGroup("変更前の\(request.field.title)") {
                MarkdownDocumentView(markdown: request.original)
              }
            }
            MarkdownDocumentView(markdown: proposal)
              .accessibilityIdentifier("record.aiEdit.proposal")
          }
          Section {
            Button("変更を保存") {
              guard model.applyRecordAIEdit(request, replacement: proposal) else {
                status = "保存できませんでした。記録や下書きの状態を確認し、変更案を作り直してください。"
                return
              }
              dismiss()
              onSave()
            }
            .accessibilityIdentifier("record.aiEdit.save")
          }
        }
      }
      .navigationTitle("変更案")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton(isGenerating ? "変更案の作成を停止" : "閉じる", icon: .xmark) { dismiss() }
        }
      }
    }
    .task {
      let result = await request.propose(in: model)
      guard !Task.isCancelled else { return }
      isGenerating = false
      switch result {
      case .answer(let text) where text == request.original.trimmingCharacters(in: .whitespacesAndNewlines):
        status = "本文に変更はありませんでした。"
      case .answer(let text):
        proposal = text
      case .failure(let failure):
        status = failure == .cancelled ? AIAnswerFailure.contextChanged.message : failure.message
      }
    }
  }
}
