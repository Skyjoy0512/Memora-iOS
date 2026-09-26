import SwiftUI

/// The always-available way to ask about whatever is on screen. It sits on the
/// floating control layer with the bottom bar, so it uses the same glass.
struct QuickAIComposer: View {
  @Environment(MemoraModel.self) private var model
  var scope: AIQueryScope
  /// Lets the bottom bar step aside while someone is typing.
  @Binding var isComposing: Bool
  /// Keeps the keyboard up after sending on the Ask AI tab. The field is never
  /// focused on its own, so switching tabs does not raise the keyboard.
  var keepsFocusAfterSubmit = false
  @State private var attachment: AIAttachment?
  /// The question handed to the focused screen. It is built when the sheet
  /// opens, so clearing the composer afterwards cannot empty what is being asked.
  @State private var pendingQuestion: AIQuestionRequest?

  var body: some View {
    // The draft lives in the model, so rebuilding this view or leaving the tab
    // does not lose what was being typed.
    @Bindable var model = model

    return AIComposerBar(
      text: $model.composerDraft,
      attachment: $attachment,
      placeholder: placeholder,
      keepsFocusAfterSubmit: keepsFocusAfterSubmit,
      onSubmit: submit(attachment:)
    ) { focused in
      isComposing = focused
    }
    .sheet(item: $pendingQuestion) { request in
      AIQuestionView(request: request)
    }
  }

  /// Naming the scope saves a trip to the range picker in the common case.
  private var placeholder: String {
    switch scope {
    case .file(let meetingID):
      model.meeting(id: meetingID).map { "「\($0.title)」に質問" } ?? "この会議に質問"
    case .space(let spaceID):
      model.space(id: spaceID).map { "「\($0.name)」に質問" } ?? "このプロジェクトに質問"
    case .global:
      "Ask Anything"
    }
  }

  private var canSend: Bool {
    !model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
  }

  /// True when the send is accepted; the composer clears the field only then,
  /// so a question typed while an answer is on its way is not lost.
  private func submit(attachment submitted: AIAttachment?) -> Bool {
    guard canSend else { return false }

    // On the Ask AI tab the question joins the chat; elsewhere it opens the
    // focused answer sheet.
    if scope == .global, model.isAskAIPresented {
      let trimmed = model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      return model.sendAIChat(
        trimmed.isEmpty ? "この添付を確認して" : trimmed,
        attachment: submitted
      )
    }

    // The request is built from what is on screen now; the composer is only
    // cleared by the bar once this returns true.
    let trimmed = model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    pendingQuestion = AIQuestionRequest(question: trimmed, scope: scope, attachment: submitted)
    return true
  }
}
