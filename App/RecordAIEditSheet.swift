import SwiftUI

struct RecordAIEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var recordID: UUID
  var initialField: RecordAIEdit.Field
  var onSave: (RecordAIEdit.Field) -> Void

  @State private var selectedField: RecordAIEdit.Field?
  @State private var instruction = ""
  @State private var request: RecordAIEdit?
  @State private var pendingCloudRequest: RecordAIEdit?
  @State private var proposal: String?
  @State private var status: String?
  @State private var isGenerating = false
  @State private var generationTask: Task<Void, Never>?
  @FocusState private var isInstructionFocused: Bool

  private var field: RecordAIEdit.Field { selectedField ?? initialField }

  var body: some View {
    let fields = model.meeting(id: recordID).map { meeting in
      RecordAIEdit.Field.allCases.filter { $0.isEditable(in: meeting) }
    } ?? []
    NavigationStack {
      Form {
        Section {
          Picker("編集する内容", selection: Binding(get: { field }, set: { selectedField = $0 })) {
            ForEach(fields) { option in Text(option.title).tag(option) }
          }
          TextField("例：決定事項を箇条書きにして", text: $instruction, axis: .vertical)
            .accessibilityLabel("AIへの編集指示")
            .accessibilityIdentifier("record.aiEdit.instruction")
            .focused($isInstructionFocused)
            .lineLimit(3...6)
        }
        .disabled(isGenerating)

        if isGenerating {
          Section {
            ProgressView("変更案を作成中…")
            Button("停止") {
              generationTask?.cancel()
              isGenerating = false
            }
          }
        } else {
          Button("変更案を作成", action: prepare)
            .disabled(!fields.contains(field) || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("record.aiEdit.generate")
        }

        if let status {
          Text(status).foregroundStyle(.secondary)
        }

        if let request, let proposal {
          Section {
            if !request.original.isEmpty {
              DisclosureGroup("変更前の\(request.field.title)") {
                MarkdownDocumentView(markdown: request.original)
              }
            }
            MarkdownDocumentView(markdown: proposal)
              .accessibilityIdentifier("record.aiEdit.proposal")
          } header: {
            Text("変更案")
          }
          Section {
            Button("変更を保存") {
              guard model.applyRecordAIEdit(request, replacement: proposal) else {
                status = "保存できませんでした。記録や下書きの状態を確認し、変更案を作り直してください。"
                return
              }
              onSave(request.field)
              dismiss()
            }
            .accessibilityIdentifier("record.aiEdit.save")
          }
        }
      }
      .navigationTitle("AIに編集を指示")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .onChange(of: field) { _, _ in clearProposal() }
      .onChange(of: instruction) { _, _ in clearProposal() }
      .confirmationDialog("外部AIで変更案を作成しますか？", isPresented: Binding(
        get: { pendingCloudRequest != nil }, set: { if !$0 { pendingCloudRequest = nil } }
      ), titleVisibility: .visible, presenting: pendingCloudRequest) { request in
        Button("送信して変更案を作成") { generate(request) }
        Button("キャンセル", role: .cancel) {}
      } message: { request in
        Text("編集指示と現在の\(request.field.title)を\(request.modelLabel)に送ります。利用料金が発生する場合があります。")
      }
    }
    .onDisappear { generationTask?.cancel() }
  }

  private func clearProposal() {
    request = nil
    proposal = nil
    status = nil
  }

  private func prepare() {
    clearProposal()
    let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let meeting = model.meeting(id: recordID) else { return }
    let request = RecordAIEdit(meeting: meeting, field: field, instruction: trimmed, model: model)
    guard request.isCurrent(in: model) else {
      status = "記録を開き直すか、編集中の下書きを保存してからお試しください。"
      return
    }
    if request.usesCloud {
      guard RecordAccessPolicy.allows(meeting.privacy, purpose: .cloudAI) else {
        status = AIAnswerFailure.recordAccessDenied.message
        return
      }
      pendingCloudRequest = request
    } else {
      generate(request)
    }
  }

  private func generate(_ request: RecordAIEdit) {
    pendingCloudRequest = nil
    isInstructionFocused = false
    generationTask?.cancel()
    isGenerating = true
    generationTask = Task {
      let result = await request.propose(in: model)
      guard !Task.isCancelled else { return }
      isGenerating = false
      switch result {
      case .answer(let text) where text == request.original.trimmingCharacters(in: .whitespacesAndNewlines):
        status = "本文に変更はありませんでした。"
      case .answer(let text):
        self.request = request
        proposal = text
      case .failure(let failure):
        status = failure == .cancelled ? AIAnswerFailure.contextChanged.message : failure.message
      }
    }
  }
}
