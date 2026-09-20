import SwiftUI

struct AIQuestionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedScope: AIQueryScope
  @State private var question: String
  @State private var attachment: AIAttachment?
  @State private var submittedQuestion: String?
  @State private var submittedAttachment: AIAttachment?
  @State private var answer: String?
  @State private var isAnswering = false

  /// A non-empty `askingQuestion` is asked on open, so arriving here from the
  /// composer or a suggestion does not need a second tap on send.
  init(scope: AIQueryScope, askingQuestion: String = "", attachment: AIAttachment? = nil) {
    _selectedScope = State(initialValue: scope)
    _question = State(initialValue: askingQuestion)
    _attachment = State(initialValue: attachment)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if let submittedQuestion {
            askedQuestion(submittedQuestion)
          } else {
            intro
          }

          if let answer {
            answerContent(answer)
              .transition(.opacity.combined(with: .move(edge: .bottom)))
          } else if submittedQuestion == nil {
            suggestions
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .padding(.bottom, 24)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: isAnswering)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: submittedQuestion)
      }
      .background(Color(uiColor: .systemBackground))
      .scrollDismissesKeyboard(.immediately)
      .safeAreaInset(edge: .bottom, spacing: 8) {
        composer
          .padding(.horizontal, 12)
          .padding(.top, 4)
      }
      .navigationTitle("Memoraに聞く")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Picker("検索範囲", selection: $selectedScope) {
            ForEach(scopeOptions, id: \.self) { scope in
              Text(label(for: scope)).tag(scope)
            }
          }
          .pickerStyle(.menu)
        }
      }
      .onAppear(perform: askIfPrefilled)
    }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("会議をまたいで、答えを探します")
        .font(.title2.bold())
        .memoraTextReveal()
      Text("回答には、元の会議と発言時刻を表示します。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .memoraTextReveal(delay: 0.08)
    }
  }

  private func askedQuestion(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(model.aiModel.title) · \(label(for: selectedScope))")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(text)
        .font(.body.weight(.medium))
        .textSelection(.enabled)

      if let submittedAttachment {
        Label(submittedAttachment.name, systemImage: "paperclip")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if isAnswering {
        HStack(spacing: 8) {
          ThinkingOrbView(state: .searching, size: 20)
          Text("会議の中から根拠を探しています")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("会議の中から根拠を探しています")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .memoraCard(radius: 18)
  }

  private func answerContent(_ answer: String) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("回答", systemImage: "sparkles")
        .font(.headline)
        .foregroundStyle(.primary)
        .memoraTextReveal()

      StreamingText(text: answer, lineSpacing: 5)

      VStack(alignment: .leading, spacing: 10) {
        Text("根拠")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(sourceMeetings) { meeting in
          NavigationLink {
            TranscriptView(meetingID: meeting.id)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "quote.bubble")
                .foregroundStyle(.primary)
              VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)
                Text("00:42 の発言")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .buttonStyle(.plain)
          .accessibilityHint("根拠になった文字起こしを開きます")
        }
      }
    }
  }

  private var suggestions: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("たとえば")
        .font(.headline)
      ForEach(Self.suggestedQuestions, id: \.self) { suggestion in
        SuggestionButton(title: suggestion) {
          question = suggestion
          ask()
        }
      }
    }
  }

  private var composer: some View {
    AIComposerBar(
      text: $question,
      attachment: $attachment,
      placeholder: "会議について質問",
      isBusy: isAnswering,
      onSubmit: ask
    )
  }

  private var canSend: Bool {
    (!question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil) && !isAnswering
  }

  private var scopeOptions: [AIQueryScope] {
    switch selectedScope {
    case .file(let meetingID):
      var scopes: [AIQueryScope] = [.file(meetingID)]
      if let spaceID = model.meeting(id: meetingID)?.spaceID {
        scopes.append(.space(spaceID))
      }
      scopes.append(.global)
      return scopes
    case .space(let spaceID):
      return [.space(spaceID), .global]
    case .global:
      return [.global] + model.spaces.prefix(2).map { .space($0.id) }
    }
  }

  private var sourceMeetings: [Meeting] {
    switch selectedScope {
    case .file(let id):
      return model.meeting(id: id).map { [$0] } ?? []
    case .space(let id):
      return Array(model.meetings.filter { $0.spaceID == id }.prefix(2))
    case .global:
      return Array(model.meetings.prefix(2))
    }
  }

  private func label(for scope: AIQueryScope) -> String {
    switch scope {
    case .file(let id):
      return model.meeting(id: id)?.title ?? "この会議"
    case .space(let id):
      return model.space(id: id)?.name ?? "このプロジェクト"
    case .global:
      return "すべての会話"
    }
  }

  private func askIfPrefilled() {
    guard submittedQuestion == nil, canSend else { return }
    ask()
  }

  private func ask() {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (!trimmed.isEmpty || attachment != nil), !isAnswering else { return }
    let effectiveQuestion = trimmed.isEmpty
      ? "「\(attachment?.name ?? "添付ファイル")」を確認して"
      : trimmed
    submittedQuestion = effectiveQuestion
    submittedAttachment = attachment
    question = ""
    attachment = nil
    answer = nil
    isAnswering = true

    Task {
      try? await Task.sleep(for: .milliseconds(850))
      let scopeLabel = label(for: selectedScope)
      let engineAnswer = await AIEngineService.answer(
        question: effectiveQuestion,
        scopeLabel: scopeLabel,
        context: model.aiContext()
      )
      let generatedAnswer = engineAnswer ?? model.aiAnswer(for: effectiveQuestion).answer
      answer = generatedAnswer
      isAnswering = false
      model.saveAIExchange(question: effectiveQuestion, answer: generatedAnswer, scopeLabel: scopeLabel)
    }
  }

  private static let suggestedQuestions = [
    "まだ決まっていないことは？",
    "田中さんのタスクを教えて",
    "先週の会議を3行でまとめて"
  ]
}

