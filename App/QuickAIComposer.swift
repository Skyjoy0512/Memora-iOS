import SwiftUI

/// The always-available way to ask about whatever is on screen. It sits on the
/// floating control layer with the bottom bar, so it uses the same glass.
struct QuickAIComposer: View {
  @Environment(MemoraModel.self) private var model
  var scope: AIQueryScope
  /// Lets the bottom bar step aside while someone is typing.
  @Binding var isComposing: Bool
  /// Keeps the keyboard up after sending on the Ask AI tab. The field is never
  /// focused on its own, so switching tabs does not raise the keyboard.
  var keepsFocusAfterSubmit = false
  /// Independent recording controls leave the idle field as a compact input.
  var compactIdle = false
  /// Focuses the field when it appears, for the full-screen Ask AI opening.
  var autofocus = false
  @State private var preparedAttachment: PreparedAIAttachment?
  @State private var attachmentPreparationTask: Task<Void, Never>?
  @State private var attachmentPreparationContext: AIComposerRequestContext?
  /// The question handed to the focused screen. It is built when the sheet
  /// opens, so clearing the composer afterwards cannot empty what is being asked.
  @State private var pendingQuestion: AIQuestionRequest?
  @State private var pendingProjectQuestion: AIQuestionRequest?
  @State private var confirmsCloudRequest = false
  @State private var isPreparingAttachment = false
  @State private var projectError: String?
  @State private var usesWebSearch = false
  @State private var mentionInput = ComposerInputState()
  @State private var dismissedMention: ComposerMentionToken?
  @State private var selectedSetup: AIPlugin?
  @State private var composerTop: CGFloat = 360
  @State private var requestsMentionMenu = false

  @ScaledMetric(relativeTo: .headline) private var menuTopClearance = MemoraSpacing.touchTarget

  var body: some View {
    // The draft lives in the model, so rebuilding this view or leaving the tab
    // does not lose what was being typed.
    @Bindable var model = model

    return VStack(spacing: MemoraSpacing.sm) {
      if model.composerDraftFailure != nil { ComposerDraftRecoveryPrompt() }
      if isPreparingAttachment, attachmentPreparationTask != nil {
        HStack {
          Text("添付を解析しています").font(.footnote).foregroundStyle(.secondary)
          Spacer()
          Button("停止", icon: .stopFill) { attachmentPreparationTask?.cancel() }
            .font(.footnote).frame(minHeight: 44)
        }.padding(.horizontal, MemoraSpacing.lg)
      } else if let token = activeMention, token != dismissedMention {
        AIPluginMenu(candidates: model.mentionCandidates(query: token.query, scope: scope),
          selectedIDs: Set(model.composerMentions.map(\.pluginID)),
          maximumHeight: min(360, max(100, composerTop - WindowSafeArea.insets.top - menuTopClearance - MemoraSpacing.md)),
          select: { selectPlugin($0, token: token) }, cancel: { dismissedMention = token })
      }
      AIComposerBar(
        text: $model.composerDraft,
        attachment: Binding(get: { model.composerAttachment }, set: { model.composerAttachment = $0 }),
        placeholder: placeholder,
        isConversation: !compactIdle && model.selectedTab == .askAI && scope == .global,
        offersIdleVoiceInput: !compactIdle,
        isBusy: isPreparingAttachment || model.activeProjectChatID.map { model.projectChatBusyIDs.contains($0) } == true,
        onStop: scope == .global && model.isAIChatResponding ? { model.stopAIChat() } : nil,
        keepsFocusAfterSubmit: keepsFocusAfterSubmit,
        autofocus: autofocus,
        acceptsExternalFocusRequest: model.selectedTab == .askAI && scope == .global,
        onSubmit: submit(attachment:),
        interactionChanged: { interacting in
          isComposing = interacting
        },
        onResearch: model.selectedTab == .askAI && scope == .global ? { usesWebSearch.toggle() } : nil,
        researchSelected: usesWebSearch,
        mentionInput: supportsMentions ? mentionInput : nil,
        onMentionMenu: supportsMentions ? { requestsMentionMenu = true; openMentionMenuIfReady() } : nil,
        removeMention: removeMention,
        mentionScope: scope,
        dismissMentionMenu: { dismissedMention = activeMention }
      )
      .disabled(model.composerDraftFailure != nil)
      .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { composerTop = $0 }
    }
    .sheet(item: $selectedSetup) { plugin in
      NavigationStack {
        AIPluginSetupView(plugin: plugin)
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            ToolbarIconButton("閉じる", icon: .xmark) { selectedSetup = nil }
          } }
      }
    }
    .onChange(of: model.composerDraft) { _, _ in
      dismissedMention = nil
      cancelStaleAttachmentPreparation()
    }
    .onChange(of: mentionInput.value) { _, _ in openMentionMenuIfReady() }
    .onChange(of: model.composerDismissRequests) { _, _ in dismissedMention = activeMention }
    .onChange(of: model.selectedTab) { _, _ in
      usesWebSearch = false
      cancelStaleAttachmentPreparation()
    }
    .onChange(of: model.aiConversationID) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: model.aiWorkspaceGeneration) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: model.activeNavigationPath) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: model.isToolsPresented) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: model.composerMentions) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: model.askAIConfiguration.engine) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: model.askAIConfiguration.llm) { _, _ in cancelStaleAttachmentPreparation() }
    .onChange(of: scope) { _, _ in cancelStaleAttachmentPreparation(); requestsMentionMenu = false; dismissedMention = nil }
    .onChange(of: model.composerAttachment) { _, _ in cancelStaleAttachmentPreparation() }
    .onDisappear { attachmentPreparationTask?.cancel() }
    .sheet(item: $pendingQuestion) { request in
      AIQuestionView(request: request)
    }
    .confirmationDialog("登録済みのAIへ送信しますか？", isPresented: $confirmsCloudRequest, titleVisibility: .visible) {
      Button("送信") {
        if let request = pendingProjectQuestion { startProjectRequest(request, allowsPaidRequest: true) }
        pendingProjectQuestion = nil
      }
      Button("キャンセル", role: .cancel) { pendingProjectQuestion = nil }
    } message: {
      Text("質問、送信が許可された資料、最近の会話を送ります。必要に応じて最大6回のAI応答で資料を調べます。利用するプロバイダーの料金が発生する場合があります。")
    }
    .alert("送信できませんでした", isPresented: Binding(get: { projectError != nil }, set: { if !$0 { projectError = nil } })) {
      Button("OK", role: .cancel) { projectError = nil }
    } message: { Text(projectError ?? "") }
  }

  private var supportsMentions: Bool {
    switch scope {
    case .global: true
    case .space(let id): model.space(id: id) != nil && model.currentTeamID == nil
    case .file: false
    }
  }

  private func openMentionMenuIfReady() {
    guard requestsMentionMenu, supportsMentions, let snapshot = mentionInput.snapshot(),
          snapshot.text == model.composerDraft, !snapshot.hasMarkedText,
          let range = Range(snapshot.selection, in: model.composerDraft) else { return }
    requestsMentionMenu = false
    if ComposerMentionToken.parse(text: snapshot.text, selection: snapshot.selection, hasMarkedText: false) != nil {
      dismissedMention = nil
      return
    }
    let prefix = model.composerDraft[..<range.lowerBound]
    let trigger = prefix.last.map { $0.isWhitespace ? "@" : " @" } ?? "@"
    model.composerDraft.replaceSubrange(range, with: trigger)
    model.composerMentionCursorRequest = ComposerCursorRequest(offset: snapshot.selection.location + trigger.utf16.count)
    dismissedMention = nil
  }

  private func removeMention(_ mention: ComposerMention) {
    guard mentionInput.snapshot()?.hasMarkedText != true, mention.isValid(in: model.composerDraft),
          let range = Range(mention.range, in: model.composerDraft) else { return }
    model.composerDraft.removeSubrange(range)
    model.composerMentionCursorRequest = ComposerCursorRequest(offset: mention.range.location)
  }
  private var attachment: AIAttachment? {
    get { model.composerAttachment }
    nonmutating set { model.composerAttachment = newValue }
  }

  private var activeMention: ComposerMentionToken? {
    guard supportsMentions, mentionInput.inputView?.isFirstResponder == true,
          let snapshot = mentionInput.value, snapshot.text == model.composerDraft else { return nil }
    return ComposerMentionToken.parse(text: snapshot.text, selection: snapshot.selection, hasMarkedText: snapshot.hasMarkedText)
  }

  private func selectPlugin(_ plugin: AIPlugin, token: ComposerMentionToken) {
    // Recheck the native marked range at the instant of the tap, not the last redraw.
    guard let snapshot = mentionInput.snapshot(), snapshot.text == model.composerDraft,
          ComposerMentionToken.parse(text: snapshot.text, selection: snapshot.selection, hasMarkedText: snapshot.hasMarkedText) == token else { return }
    guard plugin.state.isReady else {
      dismissedMention = token
      selectedSetup = plugin
      return
    }
    guard let range = Range(token.range, in: model.composerDraft) else { return }
    if model.composerMentions.contains(where: { $0.pluginID == plugin.id }) {
      model.composerDraft.removeSubrange(range)
      model.composerMentionCursorRequest = ComposerCursorRequest(offset: token.range.location)
      return
    }
    let label = plugin.name.replacingOccurrences(of: "]", with: "）").replacingOccurrences(of: "[", with: "（")
    let mention = ComposerMention(pluginID: plugin.id, label: label, range: NSRange(location: token.range.location, length: "[@\(label)]".utf16.count))
    model.composerDraft.replaceSubrange(range, with: mention.token + " ")
    model.composerMentions.append(mention)
    model.composerMentionCursorRequest = nil
    model.composerMentionCursorRequest = ComposerCursorRequest(offset: NSMaxRange(mention.range) + 1)
    dismissedMention = nil
  }

  /// Naming the scope saves a trip to the range picker in the common case.
  private var placeholder: String {
    switch scope {
    case .file(let meetingID):
      model.meeting(id: meetingID).map { "「\($0.title)」に質問" } ?? "この会議に質問"
    case .space(let spaceID):
      model.space(id: spaceID).map { "「\($0.name)」に質問" } ?? "このプロジェクトに質問"
    case .global:
      // On Ask AI itself the hint follows the mode the switch is set to.
      if model.selectedTab == .askAI {
        usesWebSearch ? "Webで調べたいこと" : "Memoraに話しかける"
      } else {
        "Memoraに質問"
      }
    }
  }

  private var canSend: Bool {
    !model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
  }

  /// True when the send is accepted; the composer clears the field only then,
  /// so a question typed while an answer is on its way is not lost.
  private func submit(attachment submitted: AIAttachment?) -> Bool {
    guard canSend else { return false }

    // A whole-library question belongs in the Ask AI chat, from whichever list
    // tab it was typed on; it switches there so the answer and the follow-ups
    // stay in one thread. A record or project question opens the answer sheet.
    if scope == .global {
      let trimmed = model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      let pluginIDs = model.composerMentions.filter { $0.isValid(in: model.composerDraft) }.map(\.pluginID)
      guard !pluginIDs.contains(where: { $0.hasPrefix("source:") }) else {
        projectError = "このソースは所属プロジェクト内のAsk AIで指定してください。入力と指定は保持しています。"
        return false
      }
      model.selectedTab = .askAI
      if usesWebSearch && submitted != nil {
        projectError = "Web検索へ添付は自動送信しません。添付を外して、検索したい内容を入力してください。"
        return false
      }
      if let submitted, AIEngineService.effectiveEngine(model.askAIConfiguration.engine) == .cloud,
         model.askAIConfiguration.llm.supportsToolCalling, !model.askAIConfiguration.llm.isMemoraIntelligence {
        startGlobalAttachmentRequest(submitted, question: trimmed.isEmpty ? "この添付を確認して" : trimmed, pluginIDs: pluginIDs)
        return false
      }
      let accepted = model.sendAIChat(
        trimmed.isEmpty ? "この添付を確認して" : trimmed,
        attachment: submitted,
        webSearchRequested: usesWebSearch,
        pluginIDs: pluginIDs
      )
      if !accepted, let reason = model.aiRequestRefusalMessage { projectError = reason }
      if accepted { usesWebSearch = false }
      return accepted
    }

    // The request is built from what is on screen now; the composer is only
    // cleared by the bar once this returns true.
    let trimmed = model.composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let request = AIQuestionRequest(question: trimmed.isEmpty ? "このソースを確認して" : trimmed, scope: scope, attachment: submitted,
      pluginIDs: model.composerMentions.filter { $0.isValid(in: model.composerDraft) }.map(\.pluginID))
    if case .file = scope, !request.pluginIDs.isEmpty {
      projectError = "この記録画面は@指定に対応していません。指定を外すか、全体またはプロジェクトのAsk AIで送信してください。"
      return false
    }
    if case .space = scope {
      if case .space(let id) = scope, model.projectMentionSelection(request.pluginIDs, projectID: id) == nil {
        projectError = "この範囲では実行できない指定があります。プロジェクト内の読み取りツール・スキル・許可されたソースを選び直してください。"
        return false
      }
      if AIEngineService.effectiveEngine(model.askAIConfiguration.engine) == .cloud {
        pendingProjectQuestion = request
        confirmsCloudRequest = true
      } else {
        startProjectRequest(request, allowsPaidRequest: false)
      }
      return false
    }
    pendingQuestion = request
    return true
  }

  private func cancelStaleAttachmentPreparation() {
    guard let context = attachmentPreparationContext, !context.isCurrent(in: model, scope: scope) else { return }
    attachmentPreparationTask?.cancel()
  }

  private func startGlobalAttachmentRequest(_ attached: AIAttachment, question: String, pluginIDs: [String]) {
    guard scope == .global, model.selectedTab == .askAI, !isPreparingAttachment,
          !model.isAIChatResponding, !model.isRestoring, !model.isStoreProtected else { return }
    guard let context = AIComposerRequestContext(scope: scope, in: model), context.attachment == attached else { return }
    let configuration = context.configuration
    attachmentPreparationContext = context
    isPreparingAttachment = true
    attachmentPreparationTask = Task { @MainActor in
      defer {
        isPreparingAttachment = false
        attachmentPreparationTask = nil
        attachmentPreparationContext = nil
      }
      guard context.isCurrent(in: model, scope: scope) else { return }
      let capabilities = ModelCapabilities.resolve(llm: configuration.llm)
      let prepared: PreparedAIAttachment
      if let cached = preparedAttachment, cached.matches(attached), cached.preparedQuestion == question { prepared = cached }
      else { prepared = await AIAttachmentText.prepare(attached, question: question, maximumCharacters: AgentAttachmentContext.characterBudget(capabilities: capabilities, task: DeepContextPolicy.task(for: question)), vocabulary: model.transcriptionVocabulary) }
      guard context.isCurrent(in: model, scope: scope) else { return }
      preparedAttachment = prepared
      guard AgentAttachmentContext.content(attachment: attached, prepared: prepared,
        maximumCharacters: AgentAttachmentContext.characterBudget(capabilities: capabilities,
          task: DeepContextPolicy.task(for: question))) != nil else {
        projectError = prepared.failure ?? "添付の本文を取得できませんでした。入力と添付は保持しています。"
        return
      }
      guard context.isCurrent(in: model, scope: scope), model.selectedTab == .askAI, scope == .global else {
        projectError = "入力・参照範囲・AI設定が変わったため送信していません。現在の設定で送信し直してください。"
        return
      }
      if model.sendAIChat(question, attachment: attached, pluginIDs: pluginIDs, preparedAttachment: prepared) {
        // This call is synchronous. A later edit is never cleared by file IO.
        model.composerDraft = ""
        model.composerAttachment = nil
        preparedAttachment = nil
      } else {
        projectError = model.aiRequestRefusalMessage ?? "送信できませんでした。入力と添付は保持しています。"
      }
    }
  }
  private func startProjectRequest(_ request: AIQuestionRequest, allowsPaidRequest: Bool) {
    guard case .space(let projectID) = request.scope, request.scope == scope, !isPreparingAttachment,
          let importContext = LocalImportContext(projectID: projectID, in: model),
          let context = AIComposerRequestContext(scope: scope, in: model) else { return }
    let trimmed = context.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard context.attachment == request.attachment,
          request.question == (trimmed.isEmpty ? "このソースを確認して" : trimmed),
          request.pluginIDs == context.mentions.filter({ $0.isValid(in: context.draft) }).map(\.pluginID) else {
      projectError = "入力が変わったため送信していません。現在の入力で送信し直してください。"
      return
    }
    let existingChat = model.activeProjectChatID.flatMap { model.projectChat(id: $0) }
    guard existingChat?.projectID == projectID || existingChat == nil else { return }
    attachmentPreparationContext = context
    isPreparingAttachment = true
    attachmentPreparationTask = Task { @MainActor in
      defer {
        isPreparingAttachment = false
        attachmentPreparationTask = nil
        attachmentPreparationContext = nil
      }
      do {
        if let attached = request.attachment {
          guard attached.files.allSatisfy({ AIAttachment.isValidSourceMetadata($0.sourceMetadata) }) else {
            projectError = "添付の元資料情報を確認できません。選択し直してください。"
            return
          }
          for file in attached.files {
            guard context.isCurrent(in: model, scope: scope), importContext.isCurrent(in: model) else { return }
            let importedID = try await model.importProjectFile(file.url, projectID: projectID,
              importContext: importContext, sourceTitle: file.name, originalURL: file.originalURL,
              sourceMetadata: file.sourceMetadata)
            guard context.isCurrent(in: model, scope: scope), importContext.isCurrent(in: model) else { return }
            guard let id = importedID else {
              projectError = "添付を保存できませんでした。質問は入力欄に残っています。"
              return
            }
            if model.source(id: id) != nil {
              await model.prepareProjectSource(id)
              guard context.isCurrent(in: model, scope: scope), importContext.isCurrent(in: model) else { return }
              guard let saved = model.source(id: id), saved.projectID == projectID, saved.canProvideText else {
                projectError = "添付は保存しましたが、参照できる本文がまだありません。ソース詳細で解析状態を確認してください。"
                return
              }
              if AIEngineService.effectiveEngine(model.askAIConfiguration.engine) == .cloud,
                 !RecordAccessPolicy.allows(saved.privacy, purpose: .cloudAI) {
                model.libraryPath.append(.projectSource(id))
                projectError = "添付は保存しました。外部AIへ送る場合は、ソース詳細のプライバシー設定で送信を許可してください。"
                return
              }
            } else {
              projectError = "音声は録音として保存しました。文字起こしと送信許可を確認してから質問してください。"
              return
            }
          }
        }
        try await model.prepareProjectQuestionLinks(request.question, context: importContext,
          cloud: AIEngineService.effectiveEngine(context.configuration.engine) == .cloud,
          isCurrent: { context.isCurrent(in: model, scope: scope) })
        guard context.isCurrent(in: model, scope: scope), importContext.isCurrent(in: model) else {
          projectError = "ワークスペース・保存先・AI設定が変わったため、質問を送信していません。現在の設定を確認してください。"
          return
        }
        guard let id = existingChat?.id ?? model.createProjectChat(projectID: projectID),
              model.sendProjectChat(id, question: request.question, allowsPaidRequest: allowsPaidRequest, pluginIDs: request.pluginIDs) else {
          projectError = "回答中でないことと質問が選択モデルの文字数上限以内であることを確認してください。"
          return
        }
        model.openProjectChat(id)
        model.composerDraft = ""
        model.composerAttachment = nil
      } catch is CancellationError {
        return
      } catch let failure as ProjectQuestionSourceFailure {
        guard context.isCurrent(in: model, scope: scope) else { return }
        if case .cloudRestricted(let id) = failure { model.libraryPath.append(.projectSource(id)) }
        projectError = failure.localizedDescription
      } catch {
        guard context.isCurrent(in: model, scope: scope) else { return }
        projectError = "添付を保存できませんでした。元ファイルと質問は残っています。"
      }
    }
  }
}
