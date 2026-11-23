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
  @State private var sourceCitations: [ProjectCitation] = []
  @State private var attachmentCitations: [AIAttachmentCitation] = []
  @State private var focusedSourceID: UUID?
  @State private var isAnswering = false
  @State private var askTask: Task<Void, Never>?
  @State private var stage = "考えています"
  @State private var startedAt: Date?
  @State private var engineLabel = ""

  /// The request carries the question, the range it was asked over, and the
  /// attachment, so what is sent cannot change while the answer is written.
  init(request: AIQuestionRequest) {
    _selectedScope = State(initialValue: request.scope)
    _focusedSourceID = State(initialValue: request.sourceID)
    _question = State(initialValue: request.question)
    _attachment = State(initialValue: request.attachment)
  }

  /// A convenience for a screen that already knows its range.
  init(scope: AIQueryScope, askingQuestion: String = "", attachment: AIAttachment? = nil) {
    self.init(request: AIQuestionRequest(question: askingQuestion, scope: scope, attachment: attachment))
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
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
            Color.clear.frame(height: 1).id(ConversationScrollFollowing.bottomID)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(MemoraSpacing.lg)
          .padding(.bottom, MemoraSpacing.xxl)
          .animation(reduceMotion ? nil : MemoraMotion.screen, value: isAnswering)
          .animation(reduceMotion ? nil : MemoraMotion.screen, value: submitted)
        }
        .modifier(ConversationScrollFollowing(proxy: proxy, latestMessageID: submitted?.id, isBusy: isAnswering))
        .background(MemoraPalette.background)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom, spacing: 8) {
          composer
            .padding(.horizontal, MemoraSpacing.md)
            .padding(.top, MemoraSpacing.xs)
        }
      }
      .navigationTitle("Memoraに聞く")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if isAnswering {
          ToolbarItem(placement: .primaryAction) {
            ToolbarIconButton("回答を停止", icon: .stopFill) {
              askTask?.cancel()
              isAnswering = false
              failureMessage = "回答を停止しました。自動で再送はしません。"
            }
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Picker(selection: $selectedScope) {
            ForEach(scopeOptions, id: \.self) { scope in
              Text(label(for: scope)).tag(scope)
            }
          } label: {
            ToolbarActionLabel("検索範囲", icon: .magnifyingglass)
          }
          .pickerStyle(.menu)
          .labelStyle(.iconOnly)
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
      Text(focusedSourceID == nil ? "資料をまたいで、答えを探します" : "この資料について質問")
        .font(.title2.bold())
      Text(focusedSourceID == nil ? "保存した本文・文字起こし・要約から、関係する部分を探して答えます。" : "この資料の原文から、根拠のある箇所を探して答えます。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private func askedQuestion(_ request: AIQuestionRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(engineLabel) · \(label(for: request.scope))")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      AIUserMessageView(text: request.effectiveQuestion, attachmentName: request.attachment?.displayName) {
        question = request.question
        attachment = request.attachment
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

      if isAnswering && (answer ?? "").isEmpty {
        ConversationStatusLine(label: stage, since: startedAt).transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func answerContent(_ answer: String) -> some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      AIResponseText(text: AnswerSourceCitation.stripped(answer), isStreaming: isAnswering)
      SourceCitationList(citations: sourceCitations)
      AttachmentCitationList(citations: attachmentCitations)

      if !sources.isEmpty {
        sourceList
      }
    }
  }

  /// A failure says what went wrong and nothing else: it has no grounds to show.
  private func failureContent(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Label("回答できませんでした", icon: .exclamationmarkTriangle)
        .font(.headline)
        .foregroundStyle(.primary)

      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The records that were sent, each with the stored lines that matched. Nothing
  /// here is invented to look like a quote; a line plays from its own time.
  private var sourceList: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Text("AIに渡した参考資料")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      ForEach(sources) { source in
        VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
          if model.isActiveDetail(source.meetingID) {
            Button {
              openInExistingDetail(source.meetingID, time: nil)
            } label: {
              AIAnswerSourceViews.Header(
                source: source,
                icon: .quoteBubble,
                iconSize: 17,
                spacing: MemoraSpacing.md,
                fontWeight: .semibold,
                lineLimit: nil,
                spacerMinLength: nil,
                trailingIcon: .arrowUpRight,
                trailingIconSize: 12
              )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AIAnswerSourceViews.spokenLabel(for: source))
            .accessibilityHint("開いている記録の文字起こしへ戻ります")
          } else {
            NavigationLink {
              TranscriptView(meetingID: source.meetingID)
            } label: {
              AIAnswerSourceViews.Header(
                source: source,
                icon: .quoteBubble,
                iconSize: 17,
                spacing: MemoraSpacing.md,
                fontWeight: .semibold,
                lineLimit: nil,
                spacerMinLength: nil,
                trailingIcon: .arrowUpRight,
                trailingIconSize: 12
              )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AIAnswerSourceViews.spokenLabel(for: source))
            .accessibilityHint("参考資料の文字起こしを開きます")
          }

          ForEach(Array(source.excerpts.enumerated()), id: \.offset) { _, excerpt in
            if model.isActiveDetail(source.meetingID) {
              Button {
                openInExistingDetail(source.meetingID, time: excerpt.start)
              } label: {
                AIAnswerSourceViews.ExcerptRow(excerpt: excerpt)
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
                AIAnswerSourceViews.ExcerptRow(excerpt: excerpt)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(MemoraFormat.duration(excerpt.start))、\(excerpt.text)")
              .accessibilityHint("この位置から再生します")
            }
          }
        }
        .padding(MemoraSpacing.md)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
      }
    }
  }

  /// Closes the sheet and asks the record already on screen to move to its
  /// transcript, so a second copy of it is never stacked and the open player is
  /// the one that seeks.
  private func openInExistingDetail(_ meetingID: UUID, time: TimeInterval?) {
    dismiss()
    model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meetingID, time: time)
  }

  private var suggestions: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("たとえば")
        .font(.headline)
      ForEach(focusedSourceID == nil ? Self.suggestedQuestions : ["要約して", "詳しく説明して"], id: \.self) { suggestion in
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
      placeholder: focusedSourceID == nil ? "資料について質問" : "この資料について質問",
      isBusy: isAnswering,
      onSubmit: { submittedAttachment in ask(attachment: submittedAttachment) }
    )
  }

  private var canSend: Bool {
    (!question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil) && !isAnswering
  }

  private var scopeOptions: [AIQueryScope] {
    if focusedSourceID != nil { return [selectedScope] }
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
    if let id = focusedSourceID { return model.source(id: id)?.title ?? "この資料" }
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
      attachment: attachmentToSend, sourceID: focusedSourceID
    )
    submitted = request
    question = ""
    attachment = nil
    answer = nil
    failureMessage = nil
    sources = []
    sourceCitations = []
    attachmentCitations = []
    unsupportedAttachmentNote = nil
    contextNote = nil
    isAnswering = true

    let configuration = model.askAIConfiguration
    let generation = model.aiWorkspaceGeneration
    let engine = configuration.engine
    let llm = configuration.llm
    startedAt = .now
    engineLabel = AIEngineService.modelLabel(engine: engine, llm: llm) ?? AIEngineService.effectiveEngine(engine).label
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
          if model.aiWorkspaceGeneration != generation {
            answer = nil
            sources = []
            sourceCitations = []
            attachmentCitations = []
            failureMessage = AIAnswerFailure.contextChanged.message
          }
        }
      }
      guard !Task.isCancelled, model.aiWorkspaceGeneration == generation else { return }

      let outcome = await model.answer(
        request: request,
        scopeLabel: label(for: request.scope),
        allowedMeetings: allowed,
        tasks: scopedTasks,
        history: "",
        engine: engine,
        llm: llm,
        onAttachmentReady: { file in
          if submitted?.id == request.id { submitted?.attachment = file }
        },
        onStage: { value in
          guard !Task.isCancelled, submitted?.id == request.id, model.aiWorkspaceGeneration == generation else { return }
          if stage != value { stage = value }
        },
        onText: { text in
          guard !Task.isCancelled, submitted?.id == request.id, model.aiWorkspaceGeneration == generation else { return }
          answer = text
        }
      )
      guard !Task.isCancelled, submitted?.id == request.id, model.aiWorkspaceGeneration == generation else { return }
      unsupportedAttachmentNote = outcome.unsupportedAttachmentNote
      contextNote = outcome.contextNote

      switch outcome.result {
      case .answer(let text):
        answer = text
        sources = outcome.sources
        sourceCitations = outcome.sourceCitations
        attachmentCitations = outcome.attachmentCitations
        model.saveAIExchange(
          question: outcome.question,
          answer: text,
          scopeLabel: outcome.scopeLabel,
          engineLabel: outcome.details.engineLabel,
          modelLabel: outcome.details.modelLabel, sourceCitations: outcome.sourceCitations,
          attachmentCitations: outcome.attachmentCitations, attachment: submitted?.attachment
        )
      case .failure(let failure):
        guard failure != .cancelled else { return }
        failureMessage = failure.message
        if question.isEmpty { question = request.question; attachment = request.attachment }
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
