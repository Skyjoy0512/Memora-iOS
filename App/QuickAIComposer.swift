import SwiftUI

struct QuickAIComposer: View {
  var scope: AIQueryScope
  @State private var mode = ComposerMode.quick
  @State private var modelChoice = AIModelChoice.fast
  @State private var question = ""
  @State private var isListening = false
  @State private var isQuestionPresented = false

  var body: some View {
    VStack(spacing: 7) {
      HStack(spacing: 8) {
        Picker("AIモード", selection: $mode) {
          ForEach(ComposerMode.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.menu)
        .font(.caption.weight(.semibold))

        Spacer()

        Picker("AIモデル", selection: $modelChoice) {
          ForEach(AIModelChoice.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.menu)
        .font(.caption.weight(.medium))
      }
      .padding(.horizontal, 2)

      HStack(spacing: 6) {
        TextField(mode.placeholder, text: $question, axis: .vertical)
          .lineLimit(1...3)
          .submitLabel(.send)
          .onSubmit(submit)

        Button(isListening ? "音声入力を停止" : "音声で入力", systemImage: isListening ? "waveform" : "mic") {
          toggleVoiceInput()
        }
        .labelStyle(.iconOnly)
        .frame(width: 44, height: 44)
        .foregroundStyle(isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        .symbolEffect(.variableColor.iterative, isActive: isListening)

        Button("送信", systemImage: "arrow.up") {
          submit()
        }
        .labelStyle(.iconOnly)
        .frame(width: 44, height: 44)
        .foregroundStyle(Color(uiColor: .systemBackground))
        .background(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary), in: Circle())
        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.leading, 13)
      .padding(.trailing, 5)
      .padding(.vertical, 4)
      .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .padding(9)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Color(uiColor: .separator).opacity(0.7), lineWidth: 0.5)
    }
    .sheet(isPresented: $isQuestionPresented) {
      AIQuestionView(scope: scope, suggestedQuestion: question)
    }
  }

  private func submit() {
    guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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

private enum AIModelChoice: String, CaseIterable, Identifiable {
  case fast
  case deep
  case local

  var id: Self { self }

  var label: String {
    switch self {
    case .fast:
      "M-Fast"
    case .deep:
      "M-Deep"
    case .local:
      "On-device"
    }
  }
}
