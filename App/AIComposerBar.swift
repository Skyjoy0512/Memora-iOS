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
  /// The Ask AI layout keeps two rows; the field row grows with the taller
  /// composer instead of leaving the extra height to the controls.
  private static let stackedFieldHeight: CGFloat = 32

  /// Open while typing, or while there is text or an attachment to send.
  private var isExpanded: Bool {
    isFieldFocused || hasContent || speechInput.isListening
  }

  // A waiting draft is not active editing: keep navigation available after blur.
  private var isInteracting: Bool { isFieldFocused || speechInput.isListening }
  private var usesStackedLayout: Bool { isConversation || isExpanded }

  private var cornerRadius: CGFloat {
    usesStackedLayout ? MemoraRadius.composer : Self.collapsedHeight / 2
  }

  private var textField: some View {
    TextField(placeholder, text: $text, selection: $textSelection, axis: .vertical)
      .font(.body)
      .lineLimit(AIComposerLayoutPolicy.lines(isExpanded: isExpanded, isTall: isEditorTall,
        lineHeight: editorLineHeight))
      .submitLabel(.send)
      .onSubmit(submit)
      .focused($isFieldFocused)
      .accessibilityLabel("メッセージ")
      .accessibilityHint(contextHint)
      .accessibilityIdentifier("ai.composer.input")
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

      // Conversation controls stay below the field even without focus. The
      // native field keeps its identity while compact contextual controls move.
      HStack(alignment: .center, spacing: 4) {
        if !usesStackedLayout {
          Color.clear.frame(width: 44, height: 44)
            .accessibilityHidden(true)
        }

        textField

        if !usesStackedLayout {
          if onResearch != nil {
            researchButton
              .matchedGeometryEffect(id: "research", in: controlsNamespace)
          }
          if offersIdleVoiceInput || onStop != nil || isBusy || speechInput.isListening {
            actionButton
              .matchedGeometryEffect(id: "action", in: controlsNamespace)
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
          if isEditorTall || AIComposerLayoutPolicy.offersExpansion(for: text) {
            MemoraIconButton(isEditorTall ? "入力欄を小さくする" : "入力欄を広げる",
              icon: isEditorTall ? .chevronDown : .chevronUp) {
              isEditorTall.toggle()
            }
            .accessibilityValue(isEditorTall ? "拡大" : "通常")
          }
          Spacer(minLength: 8)
          if onResearch != nil {
            researchButton
              .matchedGeometryEffect(id: "research", in: controlsNamespace)
          }
          actionButton
            .matchedGeometryEffect(id: "action", in: controlsNamespace)
        }
        .padding(.horizontal, MemoraSpacing.sm)
        .padding(.bottom, MemoraSpacing.sm)
        .transition(.opacity)
      }
    }
    .background { listeningBackdrop }
    .memoraGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
      interactive: true, backed: false)
    // The native menu must sit outside the glass's foreground; otherwise iOS
    // lifts the whole composer as its source and hides it while the menu is open.
    .overlay(alignment: usesStackedLayout ? .bottomLeading : .leading) {
      attachmentMenu
        .padding(.leading, usesStackedLayout ? MemoraSpacing.sm : MemoraSpacing.xs)
        .padding(.bottom, usesStackedLayout ? MemoraSpacing.sm : 0)
    }
    .preservesComposerFocus()
    .animation(reduceMotion ? nil : MemoraMotion.control, value: attachment)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: hasContent)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: speechInput.isListening)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isExpanded)
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
      speechInput.stop()
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
        let generation = model.aiWorkspaceGeneration
        let previous = attachment
        Task {
          do {
            guard (previous?.files.count ?? 0) < 10 else { importErrorMessage = "添付は10件までです。"; return }
            let file = try await model.importAIPhoto(data: edited, fileExtension: "jpg")
            guard generation == model.aiWorkspaceGeneration, attachment == previous, !model.isRestoring, !model.isStoreProtected else {
              try? FileManager.default.removeItem(at: file.url); return
            }
            if attachment == nil { attachment = file } else { attachment?.append(file) }
          } catch { importErrorMessage = error.localizedDescription }
        }
      }
    }
    .alert("添付できませんでした", isPresented: importErrorPresented) {
      Button("OK") { importErrorMessage = nil }
    } message: {
      Text(importErrorMessage ?? "")
    }
    .alert("音声入力を利用できません", isPresented: speechErrorPresented) {
      Button("OK") { speechInput.clearError() }
    } message: {
      Text(speechInput.errorMessage ?? "")
    }
  }

  /// While the mic is live a glow gathers along the bottom edge, reacting to
  /// the voice without changing the card's appearance.
  @ViewBuilder
  private var listeningBackdrop: some View {
    if speechInput.isListening {
      VoiceGlow(level: speechInput.audioLevel)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    AIComposerAttachmentButton(offersMentions: onMentionMenu != nil) {
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
    case .integrations: isIntegrationsPresented = true
    case .photo: isPhotoPickerPresented = true
    case .audio: isAudioImporterPresented = true
    case .file: isImporterPresented = true
    }
  }

  private var researchButton: some View {
    Toggle(isOn: Binding(get: { researchSelected }, set: { _ in
      InteractionFeedback.shared.send(.tap)
      onResearch?()
    })) {
      HStack(spacing: 5) {
        ToolbarIconGlyph(icon: .magnifyingglass)
        if researchSelected { Text("Web").font(.caption.weight(.medium)) }
      }
      .padding(.horizontal, researchSelected ? 10 : 0)
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
        toggleSpeechInput()
      }
    } label: {
      Group {
        if onStop == nil, !canSend, !isBusy, !speechInput.isListening {
          Image(icon: .mic, size: MemoraIconMetrics.glyph)
        } else {
          Image(icon: actionSymbol)
        }
      }
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(onStop != nil || canSend || isBusy || speechInput.isListening
          ? MemoraPalette.actionLabel : MemoraPalette.textPrimary)
        .contentTransition(.opacity)
        .frame(width: 36, height: 36)
        .background(Circle().fill(onStop != nil || canSend || isBusy || speechInput.isListening
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
    return speechInput.isListening ? "音声入力を停止" : "音声で入力"
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
    // A recording owns the shared audio session, so voice input waits its turn
    // rather than stopping the recording.
    guard !model.isRecording else {
      speechInput.refuse("録音中は音声入力を使用できません。録音を終えてからお試しください。")
      return
    }
    Task {
      await speechInput.toggle { transcript in
        text = transcript
      }
    }
  }

  private func submit() {
    guard canSend, (mentionInput ?? fallbackInput).snapshot()?.hasMarkedText != true else { return }
    speechInput.stop()
    guard onSubmit(attachment) else { return }
    InteractionFeedback.shared.send(.tap)
    text = ""
    attachment = nil
    // The Ask AI chat keeps the keyboard up for the next turn; a sheet does not.
    isFieldFocused = keepsFocusAfterSubmit
  }

  private func importFile(_ result: Result<[URL], any Error>) {
    let generation = model.aiWorkspaceGeneration
    let conversationID = model.aiConversationID
    let previous = attachment
    Task { @MainActor in
      var created: [AIAttachment] = []
      do {
        let urls = try result.get()
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
        guard model.aiWorkspaceGeneration == generation, model.currentTeamID == nil,
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
