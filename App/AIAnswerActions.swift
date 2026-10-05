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

      ShareLink(item: AnswerCitations.stripped(message.text)) {
        Label("共有", icon: .squareAndArrowUp)
      }

      Button("回答を資料に保存", icon: .docText) {
        let document = MemoraDocument(title: "Ask AIの回答", kind: .document, markdown: message.text)
        if model.addDocument(document) { savedDocument = document }
        else { saveError = true }
      }

      if model.canRetryAIAnswer(message.id) {
        Button("もう一度回答", icon: .arrowClockwise) {
          model.retryAIAnswer(message.id)
        }
      }
    }
    .labelStyle(.iconOnly)
    .buttonStyle(AnswerActionStyle())
    .foregroundStyle(.secondary)
    // The first icon lines up with the answer's text, not its tap area.
    .padding(.leading, -9)
    .sensoryFeedback(.success, trigger: didCopy) { _, copied in copied }
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
  }

  private func copy() {
    UIPasteboard.general.string = AnswerCitations.stripped(message.text)
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
