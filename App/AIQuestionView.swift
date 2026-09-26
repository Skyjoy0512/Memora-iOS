import SwiftUI

struct AIQuestionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedScope: AIQueryScope
  @State private var question: String
  @State private var attachment: AIAttachment?
  @State private var submitted: AIQuestionRequest?
  @State private var answer: String?
  @State private var failureMessage: String?
  @State private var unsupportedAttachmentNote: String?
  @State private var contextNote: String?
  @State private var sources: [AIChatSource] = []
  @State private var isAnswering = false
  @State private var askTask: Task<Void, Never>?

  /// The request carries the question, the range it was asked over, and the
  /// attachment, so what is sent cannot change while the answer is written.
  init(request: AIQuestionRequest) {
    _selectedScope = State(initialValue: request.scope)
    _question = State(initialValue: request.question)
    _attachment = State(initialValue: request.attachment)
  }

  /// A convenience for a screen that already knows its range.
  init(scope: AIQueryScope, askingQuestion: String = "", attachment: AIAttachment? = nil) {
    self.init(request: AIQuestionRequest(question: askingQuestion, scope: scope, attachment: attachment))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if let submitted {
            askedQuestion(submitted)
          } else {
            intro
          }

          if let failureMessage {
            failureContent(failureMessage)
              .transition(.opacity.combined(with: .move(edge: .bottom)))
          } else if let answer {
            answerContent(answer)
              .transition(.opacity.combined(with: .move(edge: .bottom)))
          } else if submitted == nil {
            suggestions
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .padding(.bottom, 24)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: isAnswering)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: submitted)
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
      .onDisappear {
        // Leaving the screen stops the request; its result must not be applied.
        askTask?.cancel()
        askTask = nil
      }
    }
  }

  private var intro: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("会議をまたいで、答えを探します")
        .font(.title2.bold())
        .memoraTextReveal()
      Text("会議の要約・発言・タスクから、関係する部分を探して答えます。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .memoraTextReveal(delay: 0.08)
    }
  }

  private func askedQuestion(_ request: AIQuestionRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(model.askAIModelName) · \(label(for: request.scope))")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(request.effectiveQuestion)
        .font(.body.weight(.medium))
        .textSelection(.enabled)

      if let attachment = request.attachment {
        Label(attachment.name, icon: .paperclip)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let unsupportedAttachmentNote {
        Text(unsupportedAttachmentNote)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let contextNote {
        Text(contextNote)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if isAnswering {
        HStack(spacing: 8) {
          ThinkingOrbView(state: .searching, size: 20)
          Text("会議の中から参考資料を探しています")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("会議の中から参考資料を探しています")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .memoraCard(radius: 18)
  }

  private func answerContent(_ answer: String) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("回答", icon: .sparkles)
        .font(.headline)
        .foregroundStyle(.primary)
        .memoraTextReveal()

      StreamingText(text: answer, lineSpacing: 5)

      if !sources.isEmpty {
        sourceList
      }
    }
  }

  /// A failure says what went wrong and nothing else: it has no grounds to show.
  private func failureContent(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("回答できませんでした", icon: .exclamationmarkTriangle)
        .font(.headline)
        .foregroundStyle(.primary)

      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .memoraCard(radius: 18)
  }

  /// The records that were sent, each with the stored lines that matched. Nothing
  /// here is invented to look like a quote; a line plays from its own time.
  private var sourceList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("AIに渡した参考資料")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(sources) { source in
        VStack(alignment: .leading, spacing: 6) {
          if model.isActiveDetail(source.meetingID) {
            Button {
              openInExistingDetail(source.meetingID, time: nil)
            } label: {
              sourceHeader(source)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sourceAccessibilityLabel(source))
            .accessibilityHint("開いている記録の文字起こしへ戻ります")
          } else {
            NavigationLink {
              TranscriptView(meetingID: source.meetingID)
            } label: {
              sourceHeader(source)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sourceAccessibilityLabel(source))
            .accessibilityHint("参考資料の文字起こしを開きます")
          }

          ForEach(Array(source.excerpts.enumerated()), id: \.offset) { _, excerpt in
            if model.isActiveDetail(source.meetingID) {
              Button {
                openInExistingDetail(source.meetingID, time: excerpt.start)
              } label: {
                excerptRow(excerpt)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(MemoraFormat.duration(excerpt.start))、\(excerpt.text)")
              .accessibilityHint("開いている記録のこの位置から再生します")
            } else {
              NavigationLink {
                MeetingDetailView(
                  meetingID: source.meetingID,
                  initialPlaybackStart: excerpt.start,
                  showsLocalPlaybackBar: true
                )
              } label: {
                excerptRow(excerpt)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(MemoraFormat.duration(excerpt.start))、\(excerpt.text)")
              .accessibilityHint("この位置から再生します")
            }
          }
        }
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
    }
  }

  private func sourceHeader(_ source: AIChatSource) -> some View {
    HStack(spacing: 10) {
      Image(icon: .quoteBubble)
        .foregroundStyle(.primary)
      Text(source.title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
      Spacer()
      Image(icon: .arrowUpRight)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
  }

  private func excerptRow(_ excerpt: AIChatSource.Excerpt) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(MemoraFormat.duration(excerpt.start))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      Text(excerpt.text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Closes the sheet and asks the record already on screen to move to its
  /// transcript, so a second copy of it is never stacked and the open player is
  /// the one that seeks.
  private func openInExistingDetail(_ meetingID: UUID, time: TimeInterval?) {
    dismiss()
    model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meetingID, time: time)
  }

  private func sourceAccessibilityLabel(_ source: AIChatSource) -> String {
    var parts = [source.title]
    parts.append(contentsOf: source.excerpts.map { MemoraFormat.duration($0.start) + "、" + $0.text })
    return parts.joined(separator: "、")
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
      onSubmit: { submittedAttachment in ask(attachment: submittedAttachment) }
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
    guard submitted == nil, canSend else { return }
    ask()
  }

  /// Returns true when it starts answering, so the composer clears the field
  /// only when the question is actually taken.
  @discardableResult
  private func ask(attachment submittedAttachment: AIAttachment? = nil) -> Bool {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let attachmentToSend = submittedAttachment ?? attachment
    guard (!trimmed.isEmpty || attachmentToSend != nil), !isAnswering else { return false }

    // Everything the answer depends on is captured here, so changing the range
    // on screen while it is being written cannot change what was asked.
    let request = AIQuestionRequest(
      question: trimmed,
      scope: selectedScope,
      attachment: attachmentToSend
    )
    submitted = request
    question = ""
    attachment = nil
    answer = nil
    failureMessage = nil
    sources = []
    unsupportedAttachmentNote = nil
    contextNote = nil
    isAnswering = true

    let configuration = model.askAIConfiguration
    let engine = configuration.engine
    let llm = configuration.llm
    let allowed = MemoraModel.meetings(in: request.scope, from: model.meetings)
    // A whole-library question reaches tasks that are not tied to a record too;
    // a single record or project reaches only its own.
    let scopedTasks: [MemoraTask]
    if case .global = request.scope {
      scopedTasks = MemoraModel.openTasks(in: .all, from: model.tasks, meetings: model.meetings)
    } else {
      scopedTasks = MemoraModel.tasks(in: allowed, from: model.tasks)
    }

    askTask?.cancel()
    askTask = Task {
      defer {
        // Whatever ends this task — an answer, a failure, or a newer question —
        // only the request that owns the screen clears the answering state.
        if submitted?.id == request.id {
          isAnswering = false
        }
      }
      try? await Task.sleep(for: .milliseconds(850))
      guard !Task.isCancelled else { return }

      let outcome = await model.answer(
        request: request,
        scopeLabel: label(for: request.scope),
        allowedMeetings: allowed,
        tasks: scopedTasks,
        history: "",
        engine: engine,
        llm: llm
      )
      guard !Task.isCancelled, submitted?.id == request.id else { return }
      unsupportedAttachmentNote = outcome.unsupportedAttachmentNote
      contextNote = outcome.contextNote

      switch outcome.result {
      case .answer(let text):
        answer = text
        sources = outcome.sources
        model.saveAIExchange(
          question: outcome.question,
          answer: text,
          scopeLabel: outcome.scopeLabel,
          engineLabel: outcome.details.engineLabel,
          modelLabel: outcome.details.modelLabel
        )
      case .failure(let failure):
        guard failure != .cancelled else { return }
        failureMessage = failure.message
      }
    }
    return true
  }

  private static let suggestedQuestions = [
    "まだ決まっていないことは？",
    "田中さんのタスクを教えて",
    "先週の会議を3行でまとめて"
  ]
}
