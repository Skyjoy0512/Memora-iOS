import SwiftUI

/// The always-available way to ask about whatever is on screen. It sits on the
/// floating control layer with the bottom bar, so it uses the same glass.
struct QuickAIComposer: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var scope: AIQueryScope
  /// Lets the bottom bar step aside while someone is typing.
  @Binding var isComposing: Bool
  @State private var question = ""
  @State private var isListening = false
  @State private var isQuestionPresented = false
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    // Field and send are separate glass surfaces, matching the bar and its FAB.
    // Nesting the send button inside the field's glass let vibrancy wash its
    // fill out to grey over light content.
    MemoraGlassContainer(spacing: 16) {
      HStack(alignment: .bottom, spacing: 8) {
        HStack(alignment: .bottom, spacing: 4) {
          TextField(placeholder, text: $question, axis: .vertical)
            .font(.body)
            .lineLimit(1...5)
            .submitLabel(.send)
            .onSubmit(submit)
            .focused($isFieldFocused)
            .padding(.leading, 4)
            .padding(.vertical, 11)

          // While the keyboard is up it covers the tab bar, so this slot becomes
          // the way back out. Dictation stays one tap away on the keyboard.
          Button(secondaryAction.title, systemImage: secondaryAction.symbol) {
            switch secondaryAction {
            case .dismissKeyboard:
              isFieldFocused = false
            case .startVoiceInput, .stopVoiceInput:
              toggleVoiceInput()
            }
          }
          .labelStyle(.iconOnly)
          .font(.body)
          .frame(width: 42, height: 42)
          .foregroundStyle(isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
          .symbolEffect(.variableColor.iterative, isActive: isListening)
          .contentTransition(.symbolEffect(.replace))
          .contentShape(Circle())
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .memoraGlass(in: RoundedRectangle(cornerRadius: 27, style: .continuous))

        Button("送信", systemImage: "arrow.up") {
          submit()
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .frame(width: 54, height: 54)
        .foregroundStyle(canSend ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.secondary))
        .memoraGlass(in: Circle(), tint: canSend ? .primary : nil, interactive: true)
        .disabled(!canSend)
      }
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: canSend)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isListening)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isFieldFocused)
    .sensoryFeedback(.impact(weight: .light), trigger: isListening)
    .onChange(of: isFieldFocused) {
      isComposing = isFieldFocused
    }
    .sheet(isPresented: $isQuestionPresented) {
      question = ""
    } content: {
      AIQuestionView(scope: scope, askingQuestion: question)
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
      "すべての会話に質問"
    }
  }

  private var secondaryAction: SecondaryAction {
    if isFieldFocused {
      .dismissKeyboard
    } else if isListening {
      .stopVoiceInput
    } else {
      .startVoiceInput
    }
  }

  private var canSend: Bool {
    !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func submit() {
    guard canSend else { return }
    isFieldFocused = false
    isQuestionPresented = true
  }

  private func toggleVoiceInput() {
    isListening.toggle()
    guard isListening else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(900))
      guard isListening else { return }
      question = "この会議の決定事項は？"
      isListening = false
    }
  }
}

private enum SecondaryAction {
  case startVoiceInput
  case stopVoiceInput
  case dismissKeyboard

  var title: String {
    switch self {
    case .startVoiceInput:
      "音声で入力"
    case .stopVoiceInput:
      "音声入力を停止"
    case .dismissKeyboard:
      "キーボードを閉じる"
    }
  }

  var symbol: String {
    switch self {
    case .startVoiceInput:
      "mic"
    case .stopVoiceInput:
      "waveform"
    case .dismissKeyboard:
      "keyboard.chevron.compact.down"
    }
  }
}
