import SwiftUI

/// Copy, share and ask-again for a finished answer, as small icon buttons
/// under it so they never compete with the text.
struct AIAnswerActions: View {
  @Environment(MemoraModel.self) private var model
  var message: AIChatMessage
  @State private var savedDocument: MemoraDocument?
  @State private var saveError = false
  @State private var skillDraft: MemoraSkill?

  var body: some View {
    let exportText = AnswerCitations.stripped(model.answerExportMarkdown(message))
    AIResponseActionBar(text: exportText, canRetry: model.canRetryAIAnswer(message.id),
      isSpeaking: model.isSpeakingAnswer(message.id), readAloud: {
        InteractionFeedback.shared.send(.tap)
        model.toggleAnswerSpeech(message)
      }, save: saveDocument, retry: {
        InteractionFeedback.shared.send(.tap)
        model.retryAIAnswer(message.id)
      }, saveSkill: { skillDraft = .draft(instructions: exportText) },
      saveTitle: model.savedAnswerDocument(for: message) == nil ? "回答を資料に保存" : "保存した資料を開く")
    .sheet(item: $skillDraft) { SkillEditorView(skill: $0, reviewsAnswer: true) }
    .sheet(item: $savedDocument) { document in
      NavigationStack {
        DocumentDetailView(documentID: document.id)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              ToolbarIconButton("閉じる", icon: .xmark) { savedDocument = nil }
            }
          }
      }
    }
    .alert("保存できませんでした", isPresented: $saveError) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text("保存先を確認してから、もう一度お試しください。")
    }
    .alert("読み上げできません", isPresented: Binding(
      get: { model.answerSpeech.errorMessage != nil },
      set: { if !$0 { model.answerSpeech.clearError() } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(model.answerSpeech.errorMessage ?? "")
    }
  }

  private func saveDocument() {
    if let existing = model.savedAnswerDocument(for: message) {
      savedDocument = existing
      return
    }
    let document = model.document(from: message, exportedAnswer: model.answerExportMarkdown(message))
    if model.addDocument(document) {
      InteractionFeedback.shared.send(.success)
      savedDocument = document
    } else {
      InteractionFeedback.shared.send(.error)
      saveError = true
    }
  }
}
