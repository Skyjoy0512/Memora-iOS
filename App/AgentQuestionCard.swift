import SwiftUI

/// The agent's questions, one at a time: pick a choice or write your own. A
/// single choice moves on by itself; several choices wait for 次へ. The answers
/// go back to the agent, which goes on from there.
struct AgentQuestionCard: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var request: AgentQuestionRequest

  @State private var index = 0
  @State private var picked: [Int: Set<Int>] = [:]
  @State private var custom: [Int: String] = [:]
  @State private var advanceTask: Task<Void, Never>?
  @State private var movingForward = true

  private var questions: [AgentQuestion] { request.questions }
  private var isLast: Bool { index == questions.count - 1 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        questionView(questions[index], at: index)
          .id(index)
          .transition(.asymmetric(
            insertion: .move(edge: movingForward ? .bottom : .top).combined(with: .opacity),
            removal: .move(edge: movingForward ? .top : .bottom).combined(with: .opacity)
          ))
      }
      .clipped()
      .padding(16)

      Divider()

      footer
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    .memoraCard(radius: 20)
    .overlay(alignment: .topTrailing) {
      Button {
        model.resolveAgentQuestions(nil, requestID: request.id)
      } label: {
        Image(icon: .xmark)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
          .frame(width: 36, height: 36)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("答えずに閉じる")
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.36), value: index)
    .onDisappear { advanceTask?.cancel() }
  }

  // MARK: - Question

  private func questionView(_ question: AgentQuestion, at questionIndex: Int) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(question.text)
        .font(.subheadline.weight(.semibold))
        .padding(.trailing, 28)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 2) {
        ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
          let isOn = picked[questionIndex, default: []].contains(optionIndex)
          Button {
            choose(optionIndex, in: question)
            InteractionFeedback.shared.send(.selection)
          } label: {
            HStack(spacing: 10) {
              mark(isOn: isOn, multiple: question.allowsMultiple)
              Text(option)
                .font(.subheadline)
                .foregroundStyle(isOn ? .primary : .secondary)
                .multilineTextAlignment(.leading)
              Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(isOn ? .isSelected : [])
        }

        TextField("その他（自由に入力）", text: Binding(
          get: { custom[questionIndex] ?? "" },
          set: { value in
            custom[questionIndex] = value
            // Writing an answer replaces a single choice.
            if !question.allowsMultiple, !value.isEmpty { picked[questionIndex] = [] }
          }
        ))
        .font(.subheadline)
        .padding(.leading, 28)
        .padding(.vertical, 7)
        .submitLabel(isLast ? .send : .next)
        .onSubmit { if hasAnswer { advance() } }
      }
    }
  }

  private func mark(isOn: Bool, multiple: Bool) -> some View {
    ZStack {
      if multiple {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.5)
          .background(isOn ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        Image(icon: .checkmark)
          .font(.caption2.weight(.bold))
          .foregroundStyle(Color(uiColor: .systemBackground))
          .opacity(isOn ? 1 : 0)
      } else {
        Circle()
          .strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 1.5)
          .background(isOn ? Color.primary : Color.clear, in: Circle())
        Circle()
          .fill(Color(uiColor: .systemBackground))
          .frame(width: 6, height: 6)
          .scaleEffect(isOn ? 1 : 0)
      }
    }
    .frame(width: 18, height: 18)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isOn)
  }

  // MARK: - Footer

  private var footer: some View {
    HStack(spacing: 6) {
      Button { go(to: index - 1) } label: {
        Image(icon: .chevronUp).font(.caption.weight(.semibold))
      }
      .disabled(index == 0)
      .accessibilityLabel("前の質問")

      Text("\(index + 1) / \(questions.count)")
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .contentTransition(.numericText(value: Double(index)))

      Button { go(to: index + 1) } label: {
        Image(icon: .chevronDown).font(.caption.weight(.semibold))
      }
      .disabled(isLast)
      .accessibilityLabel("次の質問")

      Spacer()

      Button("スキップ") {
        if isLast { send() } else { go(to: index + 1) }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .frame(minHeight: 36)

      Button {
        InteractionFeedback.shared.send(.tap)
        advance()
      } label: {
        Text(isLast ? "送信" : "次へ")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color(uiColor: .systemBackground))
          .padding(.horizontal, 16)
          .frame(minHeight: 36)
          .background(hasAnswer ? Color.primary : Color.secondary.opacity(0.4), in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(!hasAnswer)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
  }

  // MARK: - Answering

  private var hasAnswer: Bool {
    !picked[index, default: []].isEmpty || !(custom[index] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func choose(_ option: Int, in question: AgentQuestion) {
    if question.allowsMultiple {
      picked[index, default: []].formSymmetricDifference([option])
      return
    }
    picked[index] = [option]
    custom[index] = ""
    // A single choice moves on by itself, a moment after it is shown.
    advanceTask?.cancel()
    advanceTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(480))
      guard !Task.isCancelled else { return }
      advance()
    }
  }

  private func advance() {
    if isLast { send() } else { go(to: index + 1) }
  }

  private func go(to next: Int) {
    advanceTask?.cancel()
    let target = min(max(next, 0), questions.count - 1)
    movingForward = target > index
    index = target
  }

  private func send() {
    advanceTask?.cancel()
    let answers = questions.indices.map { questionIndex in
      let choices = picked[questionIndex, default: []].sorted().map { questions[questionIndex].options[$0] }
      let written = (custom[questionIndex] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return (choices + (written.isEmpty ? [] : [written])).joined(separator: "、")
    }
    model.resolveAgentQuestions(answers, requestID: request.id)
  }
}
