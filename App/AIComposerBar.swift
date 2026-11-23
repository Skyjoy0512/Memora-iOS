import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AIComposerBar: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var text: String
  @Binding var attachment: AIAttachment?
  var placeholder: String
  var contextHint = ""
  var isConversation = false
  var offersIdleVoiceInput = true
  var isBusy = false
  var onStop: (() -> Void)?
  /// Keeps the keyboard up after sending, so a chat can continue.
  var keepsFocusAfterSubmit = false
  /// Focuses the field when it appears, used when Ask AI opens to an empty chat.
  var autofocus = false
  var acceptsExternalFocusRequest = false
  @State private var externalFocusTask: Task<Void, Never>?
  /// Returns true when the send was accepted. Only then does the composer clear
  /// what was typed, so a refused send keeps the text and the attachment.
  var onSubmit: (AIAttachment?) -> Bool
  var focusChanged: ((Bool) -> Void)?
  var interactionChanged: ((Bool) -> Void)?
  var onResearch: (() -> Void)?
  var researchSelected = false
  var mentionInput: ComposerInputState?
  var onMentionMenu: (() -> Void)?
  var removeMention: ((ComposerMention) -> Void)?
  var mentionScope: AIQueryScope = .global
  var dismissMentionMenu: (() -> Void)?
  @State private var textSelection: TextSelection?
  @State private var fallbackInput = ComposerInputState()
  @State private var isEditorTall = false
  @ScaledMetric(relativeTo: .body) private var editorLineHeight: CGFloat = 24

  @State private var speechInput = SpeechInputService()
  @State private var isAttachmentSheetPresented = false
  @State private var restoresAttachmentFocus = false
  @State private var attachmentFocusOrigin: (workspace: UUID, conversation: UUID)?
  @State private var pendingAttachmentAction: AIComposerAttachmentAction?
  @State private var isCameraPresented = false
  @State private var capturedPhoto: Data?
  @State private var attachmentImportContext: AIComposerRequestContext?
  @State private var isModelSheetPresented = false
  @State private var startsLiveAfterModelSheet = false
  @State private var restoresModelFocus = false
  @State private var isDictating = false
  @State private var isVoiceConversation = false
  @State private var speechOriginalText = ""
  @State private var dictationOriginalText = ""
  @State private var speechTask: Task<Void, Never>?
  @State private var liveSession: LiveConversationSession?
  @AppStorage("memora.askAI.voiceSpeakerEnabled") private var isSpeakerEnabled = true
  @Environment(\.scenePhase) private var scenePhase
  @State private var isIntegrationsPresented = false
  @State private var isImporterPresented = false
  @State private var isAudioImporterPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var photoItem: PhotosPickerItem?
  @State private var editingPhoto: PhotoEditRequest?
  @State private var importErrorMessage: String?
  @FocusState private var isFieldFocused: Bool
  @Namespace private var controlsNamespace

  /// The capsule's height while collapsed; its corners make it fully round.
  private static let collapsedHeight: CGFloat = 56
  /// The focused field grows above the controls without replacing its editor.
  private static let stackedFieldHeight: CGFloat = 32

  /// Open while typing, or while there is text or an attachment to send.
  private var isExpanded: Bool {
    isFieldFocused || hasContent || speechInput.isListening || restoresAttachmentFocus || restoresModelFocus
  }

  // A waiting draft is not active editing: keep navigation available after blur.
  private var isInteracting: Bool {
    isFieldFocused || speechInput.isListening || isDictating || isVoiceConversation ||
      restoresAttachmentFocus || restoresModelFocus
  }
  private var usesStackedLayout: Bool { isExpanded }

  /// The idle Live waveform is offered only when Live is compiled in.
  private var offersLiveVoiceAction: Bool {
    isConversation && FeatureFlags.isLiveConversationEnabled
  }

  private var offersCollapsedAction: Bool {
    (offersIdleVoiceInput && (!isConversation || offersLiveVoiceAction)) ||
      onStop != nil || isBusy || speechInput.isListening
  }

  private var offersStackedAction: Bool {
    !isConversation || offersLiveVoiceAction || onStop != nil || isBusy || canSend ||
      speechInput.isListening
  }

  private var cornerRadius: CGFloat {
    usesStackedLayout ? MemoraRadius.composer : Self.collapsedHeight / 2
  }

  private var textField: some View {
    TextField("", text: $text, selection: $textSelection,
      prompt: Text(placeholder).foregroundStyle(MemoraPalette.textSecondary), axis: .vertical)
      .font(.body)
      .lineLimit(AIComposerLayoutPolicy.lines(isExpanded: isExpanded, isTall: isEditorTall,
        lineHeight: editorLineHeight))
      .submitLabel(.send)
      .onSubmit(submit)
      .focused($isFieldFocused)
      .accessibilityLabel("メッセージ")
      .accessibilityHint(contextHint)
      .accessibilityIdentifier("ai.composer.input")
      .accessibilityHidden(isDictating || isVoiceConversation)
      .padding(.vertical, MemoraSpacing.sm)
      // The field takes the width it needs and grows as text is added; the
      // controls keep their size instead of being pushed out by a long entry.
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      .background {
        ComposerInputObserver(state: mentionInput ?? fallbackInput, isActive: isFieldFocused)
      }
      .onChange(of: model.composerMentionCursorRequest) { _, request in
        guard let request, let range = Range(NSRange(location: request.offset, length: 0), in: text) else { return }
        textSelection = TextSelection(insertionPoint: range.lowerBound)
      }
  }

  var body: some View {
    VStack(spacing: 0) {
      if isConversation && isVoiceConversation, FeatureFlags.isLiveConversationEnabled,
         let liveSession {
        AIChatVoicePanel(isRunning: liveSession.isRunning, status: liveSession.phase.label,
          transcript: liveSession.transcript.isEmpty ? text : liveSession.transcript,
          session: liveSession,
          modelName: LocalVoiceModel.name, attachmentName: attachment?.displayName,
          onRemoveAttachment: { attachment = nil }, isSpeaking: liveSession.isSpeaking,
          isSpeakerEnabled: $isSpeakerEnabled,
          onAttach: { liveSession.pause(); isAttachmentSheetPresented = true },
          onModel: { liveSession.pause(); isModelSheetPresented = true },
          onMicrophone: voiceMicrophone, onStop: { liveSession.interruptResponse() }, onClose: closeVoiceConversation)
          .background { LiveConversationResponseObserver(session: liveSession) }
      }
      VStack(alignment: .leading, spacing: 0) {
        if let removeMention, !model.composerMentions.isEmpty {
          ComposerMentionStrip(mentions: model.composerMentions, scope: mentionScope, remove: removeMention)
            .padding(.horizontal, MemoraSpacing.md)
            .padding(.top, MemoraSpacing.sm)
        }
        if attachment != nil {
          attachmentStrip
            .padding(.horizontal, MemoraSpacing.lg)
            .padding(.top, MemoraSpacing.sm)

          Divider()
            .padding(.horizontal, MemoraSpacing.lg)
            .padding(.top, MemoraSpacing.sm)
        }

        // Keep the native editor mounted while controls move between rows.
        HStack(alignment: .center, spacing: 4) {
          if !usesStackedLayout {
            Color.clear.frame(width: 44, height: 44)
              .accessibilityHidden(true)
          }

          textField

          if !usesStackedLayout {
            if isConversation && offersIdleVoiceInput {
              dictationButton
            }
            if !isConversation && onResearch != nil {
              researchButton
                .matchedGeometryEffect(id: "research", in: controlsNamespace)
            }
            if offersCollapsedAction {
              actionButton
                .matchedGeometryEffect(id: "action", in: controlsNamespace, properties: isConversation ? [] : .frame)
            }
          }
        }
        .padding(.horizontal, usesStackedLayout ? MemoraSpacing.lg : MemoraSpacing.xs)
        .padding(.top, usesStackedLayout ? MemoraSpacing.sm : 0)
        .frame(minHeight: usesStackedLayout ? Self.stackedFieldHeight : Self.collapsedHeight)

        if usesStackedLayout {
          HStack(spacing: 6) {
            Color.clear.frame(width: 44, height: 44)
              .accessibilityHidden(true)
            if isConversation {
              modelButton
            }
            if isEditorTall || AIComposerLayoutPolicy.offersExpansion(for: text) {
              MemoraIconButton(isEditorTall ? "入力欄を小さくする" : "入力欄を広げる",
                icon: isEditorTall ? .chevronDown : .chevronUp) {
                isEditorTall.toggle()
              }
              .accessibilityValue(isEditorTall ? "拡大" : "通常")
            }
            Spacer(minLength: 8)
            if !isConversation && onResearch != nil {
              researchButton
                .matchedGeometryEffect(id: "research", in: controlsNamespace)
            }
            if isConversation { dictationButton }
            if offersStackedAction {
              actionButton
                .matchedGeometryEffect(id: "action", in: controlsNamespace, properties: isConversation ? [] : .frame)
            }
          }
          .padding(.horizontal, MemoraSpacing.sm)
          .padding(.bottom, MemoraSpacing.sm)
          .transition(isConversation ? .identity : .opacity)
        }
      }
      .memoraGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
        interactive: true, backed: false)
      .overlay(alignment: usesStackedLayout ? .bottomLeading : .leading) {
        attachmentMenu
          .padding(.leading, usesStackedLayout ? MemoraSpacing.sm : MemoraSpacing.xs)
          .padding(.bottom, usesStackedLayout ? MemoraSpacing.sm : 0)
      }
      .opacity(isDictating || isVoiceConversation ? 0 : 1)
      .frame(height: isDictating || isVoiceConversation ? 0 : nil)
      .clipped()
      .accessibilityHidden(isDictating || isVoiceConversation)
      .allowsHitTesting(!isDictating && !isVoiceConversation)
      if isDictating && !isVoiceConversation {
        dictationBar
      }
    }
    .preservesComposerFocus()
    .animation(reduceMotion ? nil : MemoraMotion.control, value: attachment)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: hasContent)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: speechInput.isListening)
    // Keyboard movement owns this transition on every tab.
    .animation(nil, value: isExpanded)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isEditorTall)
    .interactionFeedback(.tap, trigger: speechInput.isListening)
    .onChange(of: hasContent) { _, hasContent in
      if !hasContent { isEditorTall = false }
    }
    .onChange(of: isFieldFocused) { _, focused in
      focusChanged?(focused)
    }
    .onChange(of: isInteracting, initial: true) { _, interacting in
      interactionChanged?(interacting)
    }
    .onChange(of: model.composerDismissRequests) { _, _ in
      restoresAttachmentFocus = false
      attachmentFocusOrigin = nil
      restoresModelFocus = false
      isFieldFocused = false
    }
    .onChange(of: model.composerFocusRequest, initial: true) { _, request in
      guard acceptsExternalFocusRequest, let request, model.selectedTab == .askAI else { return }
      externalFocusTask?.cancel()
      externalFocusTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, model.composerFocusRequest == request, model.selectedTab == .askAI else { return }
        model.composerFocusRequest = nil
        isFieldFocused = true
      }
    }
    .onAppear {
      guard autofocus else { return }
      Task { @MainActor in
        // Give the field a moment to join the window before focusing it.
        try? await Task.sleep(for: .milliseconds(350))
        isFieldFocused = true
      }
    }
    .onDisappear {
      externalFocusTask?.cancel()
      endVoiceInput()
    }
    .onChange(of: model.selectedTab) { _, _ in endVoiceInput() }
    .onChange(of: model.aiConversationID) { _, _ in endVoiceInput() }
    .onChange(of: model.aiWorkspaceGeneration) { _, _ in endVoiceInput() }
    .onChange(of: model.isRestoring) { _, restoring in if restoring { endVoiceInput() } }
    .onChange(of: model.isStoreProtected) { _, protected in if protected { endVoiceInput() } }
    .onChange(of: model.composerDraftFailure) { _, failure in if failure != nil { endVoiceInput() } }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background { endVoiceInput() }
    }
    .onChange(of: isSpeakerEnabled, initial: true) { _, enabled in
      liveSession?.setSpeakerEnabled(enabled)
    }
    .sheet(isPresented: $isAttachmentSheetPresented, onDismiss: {
      let shouldRestore = restoresAttachmentFocus && model.selectedTab == .askAI &&
        attachmentFocusOrigin?.workspace == model.aiWorkspaceGeneration &&
        attachmentFocusOrigin?.conversation == model.aiConversationID &&
        !model.isToolsPresented && !model.isRestoring && !model.isStoreProtected
      restoresAttachmentFocus = false
      attachmentFocusOrigin = nil
      if let action = pendingAttachmentAction {
        pendingAttachmentAction = nil
        performAttachmentAction(action)
      } else if shouldRestore {
        isFieldFocused = true
      }
    }) {
      AIChatAttachmentSheet(researchSelected: researchSelected,
        onResearch: onResearch, onSelect: { pendingAttachmentAction = $0 })
    }
    .sheet(isPresented: $isModelSheetPresented, onDismiss: {
      if restoresModelFocus { isFieldFocused = true }
      restoresModelFocus = false
      if startsLiveAfterModelSheet {
        startsLiveAfterModelSheet = false
        startVoiceConversation()
      }
    }) {
      if isVoiceConversation, FeatureFlags.isLiveConversationEnabled, liveSession != nil {
        NavigationStack {
          LocalVoiceModelSetupView {
            startsLiveAfterModelSheet = true
            isModelSheetPresented = false
          }
        }
        .presentationDetents([.medium, .large])
      } else { AIChatModelSheet() }
    }
    .fullScreenCover(isPresented: $isCameraPresented, onDismiss: {
      guard let data = capturedPhoto else { return }
      capturedPhoto = nil
      editingPhoto = PhotoEditRequest(data: data)
    }) {
      CameraCaptureView { data in
        capturedPhoto = data
        isCameraPresented = false
      }
    }
    .fileImporter(
      isPresented: $isImporterPresented,
      allowedContentTypes: [.item],
      allowsMultipleSelection: true
    ) { result in
      importFile(result)
    }
    .fileImporter(
      isPresented: $isAudioImporterPresented,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: true
    ) { result in
      importFile(result)
    }
    .photosPicker(
      isPresented: $isPhotoPickerPresented,
      selection: $photoItem,
      matching: .images
    )
    .onChange(of: photoItem) { _, newItem in
      guard let newItem else { return }
      Task {
        await importPhoto(newItem)
      }
    }
    .sheet(isPresented: $isIntegrationsPresented) {
      NavigationStack {
        ConnectorHubView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              ToolbarIconButton("閉じる", icon: .xmark) { isIntegrationsPresented = false }
            }
          }
      }
    }
    .sheet(item: $editingPhoto) { request in
      PhotoEditorView(source: request.data) { edited in
        let context = attachmentImportContext
        let previous = attachment
        Task {
          do {
            guard let context, context.isCurrent(in: model, scope: mentionScope) else {
              importErrorMessage = "保存先や入力が変わりました。もう一度選択してください。"
              return
            }
            guard (previous?.files.count ?? 0) < 10 else { importErrorMessage = "添付は10件までです。"; return }
            let file = try await model.importAIPhoto(data: edited, fileExtension: "jpg")
            guard context.isCurrent(in: model, scope: mentionScope), attachment == previous else {
              try? FileManager.default.removeItem(at: file.url); return
            }
            if attachment == nil { attachment = file } else { attachment?.append(file) }
          } catch { importErrorMessage = error.localizedDescription }
        }
      }
    }
    .alert("添付できませんでした", isPresented: importErrorPresented) {
      Button("閉じる") { importErrorMessage = nil }
    } message: {
      Text(importErrorMessage ?? "")
    }
    .alert("音声入力を利用できません", isPresented: speechErrorPresented) {
      Button("閉じる") { speechInput.clearError() }
    } message: {
      Text(speechInput.errorMessage ?? "")
    }
  }

  private var attachmentStrip: some View {
    HStack(spacing: 8) {
      Image(icon: .paperclip)
      Text(attachment?.displayName ?? "")
        .lineLimit(1)
      Spacer(minLength: 4)
      MemoraIconButton("添付を外す", icon: .xmark) {
        InteractionFeedback.shared.send(.selection)
        attachment = nil
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var attachmentMenu: some View {
    AIComposerAttachmentButton(offersMentions: onMentionMenu != nil,
      usesChatSheet: isConversation, onPresentChatSheet: {
        restoresAttachmentFocus = isFieldFocused
        // Resigning the field can commit Japanese marked text; focus restoration must not compare draft contents.
        attachmentFocusOrigin = isFieldFocused ? (model.aiWorkspaceGeneration, model.aiConversationID) : nil
        isFieldFocused = false
        isAttachmentSheetPresented = true
      }) {
      dismissMentionMenu?()
    } onSelect: { action in
      performAttachmentAction(action)
    }
  }

  private func performAttachmentAction(_ action: AIComposerAttachmentAction) {
    InteractionFeedback.shared.send(.tap)
    switch action {
    case .mention:
      isFieldFocused = true
      onMentionMenu?()
    case .camera:
      attachmentImportContext = AIComposerRequestContext(scope: mentionScope, in: model)
      isCameraPresented = true
    case .integrations: isIntegrationsPresented = true
    case .photo:
      attachmentImportContext = AIComposerRequestContext(scope: mentionScope, in: model)
      isPhotoPickerPresented = true
    case .audio:
      attachmentImportContext = AIComposerRequestContext(scope: mentionScope, in: model)
      isAudioImporterPresented = true
    case .file:
      attachmentImportContext = AIComposerRequestContext(scope: mentionScope, in: model)
      isImporterPresented = true
    }
  }

  private var researchButton: some View {
    Toggle(isOn: Binding(get: { researchSelected }, set: { _ in
      InteractionFeedback.shared.send(.tap)
      onResearch?()
    })) {
      HStack(spacing: MemoraSpacing.xs) {
        ToolbarIconGlyph(icon: .magnifyingglass)
        if researchSelected { Text("Web").font(.caption.weight(.medium)) }
      }
      .padding(.horizontal, researchSelected ? MemoraSpacing.sm : 0)
      .frame(minWidth: 44, minHeight: 44)
      .background(.primary.opacity(researchSelected ? 0.08 : 0), in: Capsule())
      .contentShape(Capsule())
    }
    .toggleStyle(.button)
    .buttonStyle(.plain)
    .accessibilityLabel("Webで検索")
    .accessibilityValue(researchSelected ? "オン" : "オフ")
    .accessibilityHint("オンにすると、次の質問をWebで検索します。")
    .disabled(isBusy || speechInput.isListening)
  }

  private var actionButton: some View {
    Button {
      if let onStop { onStop() }
      else if canSend {
        submit()
      } else if !isBusy {
        if isConversation { startVoiceConversation() }
        else { toggleSpeechInput() }
      }
    } label: {
      Group {
        if onStop == nil, !canSend, !isBusy, !speechInput.isListening {
          Image(icon: isConversation ? .waveform : .mic, size: MemoraIconMetrics.glyph)
        } else {
          Image(icon: actionSymbol)
        }
      }
        .foregroundStyle(isConversation || onStop != nil || canSend || isBusy || speechInput.isListening
          ? MemoraPalette.actionLabel : MemoraPalette.textPrimary)
        .contentTransition(.opacity)
        .frame(width: 36, height: 36)
        .background(Circle().fill(isConversation || onStop != nil || canSend || isBusy || speechInput.isListening
          ? MemoraPalette.action : .clear))
        // The circle stays small; the target around it does not.
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(onStop == nil && (isBusy || (!canSend && model.isRecording)))
    .accessibilityLabel(actionLabel)
  }

  private var actionSymbol: MemoraIcon {
    if onStop != nil { return .stopFill }
    if isBusy { return .ellipsis }
    return canSend ? .arrowUp : .waveform
  }

  private var actionLabel: String {
    if onStop != nil { return "回答を停止" }
    if canSend { return "送信" }
    if model.isRecording { return "録音中は音声入力を使用できません" }
    return isConversation ? "音声会話を開始" : speechInput.isListening ? "音声入力を停止" : "音声で入力"
  }

  private var hasContent: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
  }

  private var canSend: Bool {
    hasContent && !isBusy && onStop == nil
  }

  private var importErrorPresented: Binding<Bool> {
    Binding(
      get: { importErrorMessage != nil },
      set: { if !$0 { importErrorMessage = nil } }
    )
  }

  private var speechErrorPresented: Binding<Bool> {
    Binding(
      get: { speechInput.errorMessage != nil },
      set: { if !$0 { speechInput.clearError() } }
    )
  }

  private func toggleSpeechInput() {
    guard !model.isRecording else {
      speechInput.refuse("録音中は音声入力を使用できません。録音を終えてからお試しください。")
      return
    }
    if speechInput.isListening { speechInput.stop(); return }
    speechOriginalText = text
    if isConversation {
      if !isDictating { dictationOriginalText = text }
      isDictating = true
      isFieldFocused = false
    }
    let generation = model.aiWorkspaceGeneration
    let conversationID = model.aiConversationID
    let prefix = speechOriginalText
    speechTask?.cancel()
    speechTask = Task {
      guard !Task.isCancelled else { return }
      await speechInput.toggle { transcript in
        guard generation == model.aiWorkspaceGeneration, conversationID == model.aiConversationID else { return }
        text = prefix + (prefix.isEmpty ? "" : "\n") + transcript
      }
      if speechInput.errorMessage != nil { isDictating = false; isVoiceConversation = false }
    }
  }

  private func startVoiceConversation() {
    guard FeatureFlags.isLiveConversationEnabled else { return }
    guard model.selectedTab == .askAI, model.currentTeamID == nil, !model.isRestoring,
          !model.isStoreProtected, model.composerDraftFailure == nil else { return }
    guard !model.isRecording else {
      speechInput.refuse("録音中はLiveを使用できません。録音を終えてからお試しください。")
      return
    }
    let session = liveSession ?? LiveConversationSession()
    liveSession = session
    session.setSpeakerEnabled(isSpeakerEnabled)
    speechTask?.cancel()
    speechInput.stop()
    model.stopAnswerSpeech()
    isVoiceConversation = true
    isDictating = false
    isFieldFocused = false
    let generation = model.aiWorkspaceGeneration
    let conversationID = model.aiConversationID
    session.validatesContext = {
      model.aiWorkspaceGeneration == generation && model.aiConversationID == conversationID &&
        model.selectedTab == .askAI && !model.isToolsPresented && model.currentTeamID == nil &&
        !model.isRestoring && !model.isStoreProtected && model.composerDraftFailure == nil
    }
    session.onUnsentTranscript = { partial in
      if text.isEmpty { text = partial }
    }
    session.onInterrupt = { id in
      guard model.aiWorkspaceGeneration == generation, model.aiConversationID == conversationID,
            model.aiMessages.last?.id == id else { return }
      model.stopAIChat()
    }
    session.onUtterance = { utterance in
      guard model.aiWorkspaceGeneration == generation, model.aiConversationID == conversationID else { return nil }
      // Existing drafts and explicit attachments need their normal review/prepare flow.
      guard text.isEmpty, attachment == nil, model.composerMentions.isEmpty, !isBusy else {
        if text.isEmpty { text = utterance }
        return nil
      }
      guard model.sendLocalVoiceChat(utterance) else {
        if text.isEmpty { text = utterance }
        return nil
      }
      return model.aiMessages.last.flatMap { $0.role == .assistant ? $0.id : nil }
    }
    guard !hasContent, !model.isAIChatResponding else { session.requireReview(); return }
    guard LocalVoiceModel.isInstalled else {
      isModelSheetPresented = true
      return
    }
    speechTask = Task { await session.start() }
  }

  private func voiceMicrophone() {
    guard FeatureFlags.isLiveConversationEnabled else { return }
    if liveSession?.isRunning == true { liveSession?.pause() }
    else { startVoiceConversation() }
  }

  private func closeVoiceConversation() {
    speechTask?.cancel()
    liveSession?.disconnect()
    isVoiceConversation = false
    isDictating = false
  }

  private func endVoiceInput() {
    startsLiveAfterModelSheet = false
    speechTask?.cancel()
    speechInput.stop()
    liveSession?.disconnect()
    isVoiceConversation = false
    isDictating = false
  }

  private var modelButton: some View {
    Button {
      restoresModelFocus = isFieldFocused
      isFieldFocused = false
      isModelSheetPresented = true
    } label: {
      HStack(spacing: MemoraSpacing.xs) {
        Text(model.askAIModelName).font(.subheadline).lineLimit(1)
        Image(icon: .chevronDown, size: 12)
      }
      .padding(.horizontal, 14).frame(minHeight: 36)
      .background(MemoraPalette.card, in: Capsule())
      .frame(minHeight: 44).contentShape(Capsule())
    }
    .buttonStyle(.plain).accessibilityLabel("モデルを選択、\(model.askAIModelName)")
    .accessibilityIdentifier("ai.composer.model")
  }

  private var dictationButton: some View {
    Button { toggleSpeechInput() } label: {
      Image(icon: .mic, size: 21)
        .frame(width: 36, height: 36)
        .background(MemoraPalette.card, in: Circle())
        .frame(width: 44, height: 44).contentShape(Circle())
    }
    .buttonStyle(.plain).disabled(isBusy || onStop != nil)
    .accessibilityLabel("音声で入力")
    .accessibilityIdentifier("ai.composer.dictate")
  }

  private var dictationBar: some View {
    HStack(spacing: 4) {
      MemoraIconButton("音声入力をキャンセル", icon: .xmark) {
        speechTask?.cancel()
        speechInput.stop(); text = dictationOriginalText; isDictating = false
      }
      AIInputWaveform(speechInput: speechInput)
      MemoraIconButton(speechInput.isListening ? "音声入力を停止" : "音声入力を再開",
        icon: speechInput.isListening ? .stopFill : .mic) {
        if speechInput.isListening { speechInput.stop() }
        else { toggleSpeechInput() }
      }
      Button {
        speechInput.stop(); isDictating = false
        submit()
      } label: {
        Image(icon: .arrowUp, size: 24)
          .foregroundStyle(.white).frame(width: 36, height: 36)
          .background(Color(red: 0.82, green: 0.30, blue: 0.16), in: Circle())
          .frame(width: 44, height: 44).contentShape(Circle())
      }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("音声入力を送信")
    }
    .padding(6)
    .memoraGlass(in: Capsule(), interactive: true, backed: false)
  }

  private func submit() {
    guard canSend, (mentionInput ?? fallbackInput).snapshot()?.hasMarkedText != true else { return }
    speechTask?.cancel()
    speechInput.stop()
    guard onSubmit(attachment) else { return }
    InteractionFeedback.shared.send(.tap)
    text = ""
    attachment = nil
    // The Ask AI chat keeps the keyboard up for the next turn; a sheet does not.
    isFieldFocused = keepsFocusAfterSubmit && !isVoiceConversation
  }

  private func importFile(_ result: Result<[URL], any Error>) {
    let generation = model.aiWorkspaceGeneration
    let conversationID = model.aiConversationID
    let previous = attachment
    let context = attachmentImportContext
    Task { @MainActor in
      var created: [AIAttachment] = []
      do {
        let urls = try result.get()
        guard let context, context.isCurrent(in: model, scope: mentionScope) else {
          importErrorMessage = "保存先や入力が変わりました。もう一度選択してください。"
          return
        }
        let capacity = 10 - (previous?.files.count ?? 0)
        guard !urls.isEmpty, urls.count <= capacity else { importErrorMessage = "添付は10件までです。"; return }
        var combined = previous
        for url in urls {
          try Task.checkCancellation()
          let available = 10 - (combined?.files.count ?? 0)
          let file = try await model.importAIAttachment(from: url, maximumFiles: available)
          created.append(file)
          guard file.files.count <= available else { throw ConversationSourceIntake.Failure.unavailable("添付は10件までです。") }
          if combined == nil { combined = file } else { combined?.append(file) }
        }
        try Task.checkCancellation()
        guard context.isCurrent(in: model, scope: mentionScope),
              model.aiWorkspaceGeneration == generation, model.currentTeamID == nil,
              model.aiConversationID == conversationID,
              !model.isRestoring, !model.isStoreProtected, attachment == previous else {
          for file in created.flatMap(\.files) { try? FileManager.default.removeItem(at: file.url) }
          importErrorMessage = "保存先や入力が変わりました。もう一度選択してください。"
          return
        }
        attachment = combined
      } catch {
        for file in created.flatMap(\.files) { try? FileManager.default.removeItem(at: file.url) }
        importErrorMessage = error.localizedDescription
      }
    }
  }

  private func importPhoto(_ item: PhotosPickerItem) async {
    guard let data = try? await item.loadTransferable(type: Data.self) else {
      photoItem = nil
      importErrorMessage = "写真を添付できませんでした。もう一度お試しください。"
      return
    }
    photoItem = nil
    // Crop and adjust before attaching.
    editingPhoto = PhotoEditRequest(data: data)
  }
}
