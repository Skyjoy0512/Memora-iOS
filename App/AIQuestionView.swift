import SwiftUI

enum AIQueryScope: Hashable {
  case file(UUID)
  case space(UUID)
  case global
}

struct AIQuestionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedScope: AIQueryScope
  @State private var question: String
  @State private var submittedQuestion: String?
  @State private var answer: String?
  @State private var isAnswering = false
  @State private var isListening = false
  @FocusState private var isFieldFocused: Bool

  /// A non-empty `askingQuestion` is asked on open, so arriving here from the
  /// composer or a suggestion does not need a second tap on send.
  init(scope: AIQueryScope, askingQuestion: String = "") {
    _selectedScope = State(initialValue: scope)
    _question = State(initialValue: askingQuestion)
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
      Text("回答には、元の会議と発言時刻を表示します。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private func askedQuestion(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label(for: selectedScope))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(text)
        .font(.body.weight(.medium))
        .textSelection(.enabled)

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
    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func answerContent(_ answer: String) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("回答", systemImage: "sparkles")
        .font(.headline)
        .foregroundStyle(.primary)

      Text(answer)
        .font(.body)
        .lineSpacing(5)
        .textSelection(.enabled)

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
    MemoraGlassContainer(spacing: 16) {
      HStack(alignment: .bottom, spacing: 8) {
        HStack(alignment: .bottom, spacing: 4) {
          TextField("会議について質問", text: $question, axis: .vertical)
            .font(.body)
            .lineLimit(1...5)
            .submitLabel(.send)
            .onSubmit(ask)
            .focused($isFieldFocused)
            .padding(.leading, 4)
            .padding(.vertical, 11)

          Button(isListening ? "音声入力を停止" : "音声で入力", systemImage: isListening ? "waveform" : "mic") {
            toggleVoiceInput()
          }
          .labelStyle(.iconOnly)
          .font(.body)
          .frame(width: 42, height: 42)
          .foregroundStyle(isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
          .symbolEffect(.variableColor.iterative, isActive: isListening)
          .contentShape(Circle())
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .memoraGlass(in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
          MemoraBorderBeam(cornerRadius: 27, strength: 0.7, active: !isAnswering)
        }

        Button("送信", systemImage: "arrow.up") {
          ask()
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
    .sensoryFeedback(.impact(weight: .light), trigger: isListening)
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

  private var canSend: Bool {
    !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAnswering
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
    guard !trimmed.isEmpty, !isAnswering else { return }
    isFieldFocused = false
    submittedQuestion = trimmed
    question = ""
    answer = nil
    isAnswering = true

    Task {
      try? await Task.sleep(for: .milliseconds(850))
      let generatedAnswer = "次に行うことは、初回録音フローの仕様確定と、Acme社へセキュリティ資料を送ることです。録音開始の速さを優先し、データは既定で端末内に保存する方針が確認されています。"
      answer = generatedAnswer
      isAnswering = false
      model.saveAIExchange(question: trimmed, answer: generatedAnswer, scopeLabel: label(for: selectedScope))
    }
  }

  private static let suggestedQuestions = [
    "まだ決まっていないことは？",
    "田中さんのタスクを教えて",
    "先週の会議を3行でまとめて"
  ]
}

private struct SuggestionButton: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
          .foregroundStyle(.primary)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: "arrow.up.left")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
      .padding(.vertical, 10)
    }
    .buttonStyle(.plain)
  }
}
