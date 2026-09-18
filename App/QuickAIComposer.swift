import SwiftUI

/// The always-available way to ask about whatever is on screen. It sits on the
/// floating control layer with the bottom bar, so it uses the same glass.
struct QuickAIComposer: View {
  @Environment(MemoraModel.self) private var model
  var scope: AIQueryScope
  /// Lets the bottom bar step aside while someone is typing.
  @Binding var isComposing: Bool
  /// Raises the keyboard when the Ask AI tab comes to the front.
  var focusRequest = false
  @State private var question = ""
  @State private var attachment: AIAttachment?
  @State private var isQuestionPresented = false

  var body: some View {
    AIComposerBar(
      text: $question,
      attachment: $attachment,
      placeholder: placeholder,
      focusRequest: focusRequest,
      onSubmit: submit
    ) { focused in
      isComposing = focused
    }
    .sheet(isPresented: $isQuestionPresented) {
      question = ""
      attachment = nil
    } content: {
      AIQuestionView(scope: scope, askingQuestion: question, attachment: attachment)
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
      "Ask AI…"
    }
  }

  private var canSend: Bool {
    !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
  }

  private func submit() {
    guard canSend else { return }
    isQuestionPresented = true
  }
}
