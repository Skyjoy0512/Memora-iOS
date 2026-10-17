import SwiftUI
import UIKit

/// Copy, share and ask-again for a finished answer, as small icon buttons
/// under it so they never compete with the text.
struct AIAnswerActions: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var message: AIChatMessage
  @State private var didCopy = false
  @State private var copyResetTask: Task<Void, Never>?
  @State private var savedDocument: MemoraDocument?
  @State private var saveError = false

  var body: some View {
    HStack(spacing: 2) {
      Button(didCopy ? "コピーしました" : "コピー", icon: didCopy ? .checkmark : .docOnDoc) {
        copy()
      }
      .contentTransition(.symbolEffect(.replace))

      ShareLink(item: AnswerCitations.stripped(NativeAIInterface.response(message.text).markdown)) {
        Label("共有", icon: .squareAndArrowUp)
      }

      Button(
        model.isSpeakingAnswer(message.id) ? "読み上げを停止" : "読み上げ",
        icon: model.isSpeakingAnswer(message.id) ? .stopFill : .speakerWave2Fill
      ) {
        InteractionFeedback.shared.send(.tap)
        model.toggleAnswerSpeech(message)
      }

      Button("回答を資料に保存", icon: .docText) {
        let document = model.document(from: message)
        if model.addDocument(document) {
          InteractionFeedback.shared.send(.success)
          savedDocument = document
        } else {
          InteractionFeedback.shared.send(.error)
          saveError = true
        }
      }

      if model.canRetryAIAnswer(message.id) {
        Button("もう一度回答", icon: .arrowClockwise) {
          InteractionFeedback.shared.send(.tap)
          model.retryAIAnswer(message.id)
        }
      }
    }
    .labelStyle(.iconOnly)
    .buttonStyle(AnswerActionStyle())
    .foregroundStyle(.secondary)
    // The first icon lines up with the answer's text, not its tap area.
    .padding(.leading, -9)
    .onDisappear { copyResetTask?.cancel() }
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

  private func copy() {
    UIPasteboard.general.string = AnswerCitations.stripped(NativeAIInterface.response(message.text).markdown)
    InteractionFeedback.shared.send(.success)
    withAnimation(reduceMotion ? nil : MemoraMotion.control) { didCopy = true }
    copyResetTask?.cancel()
    copyResetTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.6))
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : MemoraMotion.control) { didCopy = false }
    }
  }
}

/// A comfortable tap target around a small icon, dimming while pressed.
private struct AnswerActionStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body)
      .frame(width: 44, height: 44)
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.5 : 1)
  }
}
