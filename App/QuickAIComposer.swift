import SwiftUI

/// The always-available way to ask about whatever is on screen. It sits on the
/// floating control layer with the bottom bar, so it uses the same glass.
struct QuickAIComposer: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var scope: AIQueryScope
  /// Lets the bottom bar step aside while someone is typing.
  @Binding var isComposing: Bool
  @State private var mode = ComposerMode.quick
  @State private var question = ""
  @State private var isListening = false
  @State private var isQuestionPresented = false
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    HStack(spacing: 4) {
      Picker("AIモード", selection: $mode) {
        ForEach(ComposerMode.allCases) { option in
          Text(option.label).tag(option)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .font(.caption.weight(.semibold))
      .tint(.primary)
      .fixedSize()

      Divider()
        .frame(height: 18)
        .padding(.horizontal, 2)

      TextField(mode.placeholder, text: $question, axis: .vertical)
        .font(.subheadline)
        .lineLimit(1...3)
        .submitLabel(.send)
        .onSubmit(submit)
        .focused($isFieldFocused)
        .padding(.leading, 4)

      // While the keyboard is up it covers the tab bar, so this slot becomes the
      // way back out. Dictation is still one tap away on the keyboard itself.
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
      .frame(width: 40, height: 40)
      .foregroundStyle(isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
      .symbolEffect(.variableColor.iterative, isActive: isListening)
      .contentTransition(.symbolEffect(.replace))
      .contentShape(Circle())

      Button("送信", systemImage: "arrow.up") {
        submit()
      }
      .labelStyle(.iconOnly)
      .font(.body.weight(.semibold))
      .frame(width: 40, height: 40)
      .foregroundStyle(canSend ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.secondary))
      // An explicit color, not the hierarchical `.primary`, which glass renders
      // with vibrancy and washes out to grey.
      .background(canSend ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.quaternary), in: Circle())
      .scaleEffect(canSend ? 1 : 0.88)
      .disabled(!canSend)
    }
    .padding(.leading, 12)
    .padding(.trailing, 5)
    .padding(.vertical, 5)
    .memoraGlass(in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    .animation(reduceMotion ? nil : MemoraMotion.control, value: canSend)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isListening)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isFieldFocused)
    .sensoryFeedback(.impact(weight: .light), trigger: isListening)
    .onChange(of: isFieldFocused) {
      isComposing = isFieldFocused
    }
    .sheet(isPresented: $isQuestionPresented) {
      AIQuestionView(scope: scope, suggestedQuestion: question)
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
      question = mode == .quick ? "この会議の決定事項は？" : "この会議の未決事項を詳しく教えて"
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

private enum ComposerMode: String, CaseIterable, Identifiable {
  case quick
  case chat

  var id: Self { self }

  var label: String {
    switch self {
    case .quick:
      "Quick AI"
    case .chat:
      "AI Chat"
    }
  }

  var placeholder: String {
    switch self {
    case .quick:
      "すぐに質問"
    case .chat:
      "会話を続けて質問"
    }
  }
}
