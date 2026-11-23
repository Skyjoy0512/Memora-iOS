import SwiftUI

struct RecordAIEditComposer: View {
  @Environment(MemoraModel.self) private var model
  var destination: RecordAIEdit.Destination
  var close: () -> Void

  @State private var instruction = ""
  @State private var selectedField: RecordAIEdit.Field?
  @State private var pendingCloudRequest: RecordAIEdit?
  @State private var review: RecordAIEdit?
  @State private var errorMessage: String?

  var body: some View {
    let fields = model.meeting(id: destination.id).map { meeting in
      RecordAIEdit.Field.allCases.filter { $0.isEditable(in: meeting) }
    } ?? []
    let preferredField = selectedField ?? destination.field
    let field = fields.contains(preferredField) ? preferredField : fields.first ?? .notes

    AIComposerBar(text: $instruction, attachment: .constant(nil),
      placeholder: "\(field.title)の編集を指示", contextHint: "この記録の\(field.title)の変更案を作成します",
      offersIdleVoiceInput: false, autofocus: true,
      onSubmit: { _ in prepare(field: field) },
      recordEditControls: .init(field: Binding(get: { field }, set: { selectedField = $0 }), fields: fields, close: close))
    .sheet(item: $review) { request in
      RecordAIEditSheet(request: request) {
        model.recordAIEditDestination = RecordAIEdit.Destination(id: destination.id, field: request.field)
        close()
      }
    }
    .confirmationDialog("外部AIで変更案を作成しますか？", isPresented: Binding(
      get: { pendingCloudRequest != nil }, set: { if !$0 { pendingCloudRequest = nil } }
    ), titleVisibility: .visible, presenting: pendingCloudRequest) { request in
      Button("送信して変更案を作成") { review = request }
      Button("キャンセル", role: .cancel) {}
    } message: { request in
      Text("編集指示と現在の\(request.field.title)を\(request.modelLabel)に送ります。利用料金が発生する場合があります。")
    }
    .alert("変更案を作成できませんでした", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private func prepare(field: RecordAIEdit.Field) -> Bool {
    let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let meeting = model.meeting(id: destination.id) else { return false }
    let request = RecordAIEdit(meeting: meeting, field: field, instruction: trimmed, model: model)
    guard request.isCurrent(in: model) else {
      errorMessage = "記録を開き直すか、編集中の下書きを保存してからお試しください。"
      return false
    }
    if request.usesCloud {
      guard RecordAccessPolicy.allows(meeting.privacy, purpose: .cloudAI) else {
        errorMessage = AIAnswerFailure.recordAccessDenied.message
        return false
      }
      pendingCloudRequest = request
    } else {
      review = request
    }
    return true
  }
}
