import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AIComposerBar: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var text: String
  @Binding var attachment: AIAttachment?
  var placeholder: String
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
  var expansionChanged: ((Bool) -> Void)?
  var onResearch: (() -> Void)?
  var researchSelected = false
  var mentionInput: ComposerInputState?
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
  private static let collapsedHeight: CGFloat = 50

  /// Open while typing, or while there is text or an attachment to send.
  private var isExpanded: Bool {
    isFieldFocused || hasContent || speechInput.isListening
  }

  private var cornerRadius: CGFloat {
    isExpanded ? 24 : Self.collapsedHeight / 2
  }

  private var textField: some View {
    TextField(placeholder, text: $text, selection: $textSelection, axis: .vertical)
      .font(.body)
      .lineLimit(AIComposerLayoutPolicy.lines(isExpanded: isExpanded, isTall: isEditorTall,
        lineHeight: editorLineHeight))
      .submitLabel(.send)
      .onSubmit(submit)
      .focused($isFieldFocused)
      .padding(.vertical, 8)
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
      if attachment != nil {
        attachmentStrip
          .padding(.horizontal, 14)
          .padding(.top, 8)

        Divider()
          .padding(.horizontal, 14)
          .padding(.top, 6)
      }

      // Collapsed, the composer is one slim capsule: attach, the prompt and the
      // voice button. Focused or holding something, it opens into a card with
      // the text across the top and the controls on a row beneath. The text
      // field keeps its place in the tree in both, so focusing it does not
      // rebuild it and drop the keyboard; only the buttons move between rows.
      HStack(alignment: .center, spacing: 4) {
        if !isExpanded {
          attachmentMenu
            .matchedGeometryEffect(id: "attach", in: controlsNamespace)
        }

        textField

        if !isExpanded {
          if onResearch != nil {
            researchButton
              .matchedGeometryEffect(id: "research", in: controlsNamespace)
          }
          actionButton
            .matchedGeometryEffect(id: "action", in: controlsNamespace)
        }
      }
      .padding(.leading, isExpanded ? 16 : 4)
      .padding(.trailing, isExpanded ? 16 : 4)
      .padding(.top, isExpanded ? 10 : 0)
      .frame(minHeight: isExpanded ? 44 : Self.collapsedHeight)

      if isExpanded {
        HStack(spacing: 6) {
          attachmentMenu
            .matchedGeometryEffect(id: "attach", in: controlsNamespace)
          if isEditorTall || AIComposerLayoutPolicy.offersExpansion(for: text) {
            Button(isEditorTall ? "入力欄を小さくする" : "入力欄を広げる",
              icon: isEditorTall ? .chevronDown : .chevronUp) {
              isEditorTall.toggle()
            }
            .labelStyle(.iconOnly).buttonStyle(.plain)
            .frame(width: 44, height: 44)
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
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .transition(.opacity)
      }
    }
    .background { listeningBackdrop }
    .memoraGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: true, backed: false)
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
    .onChange(of: isExpanded, initial: true) { _, expanded in
      expansionChanged?(expanded)
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
      allowsMultipleSelection: false
    ) { result in
      importFile(result)
    }
    .fileImporter(
      isPresented: $isAudioImporterPresented,
      allowedContentTypes: [.audio],
      allowsMultipleSelection: false
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
        IntegrationsView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              ToolbarIconButton("閉じる", icon: .xmark) { isIntegrationsPresented = false }
            }
          }
      }
    }
    .sheet(item: $editingPhoto) { request in
      PhotoEditorView(source: request.data) { edited in
        do {
          attachment = try model.importAIPhoto(data: edited, fileExtension: "jpg")
        } catch {
          importErrorMessage = "写真を添付できませんでした。もう一度お試しください。"
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
      Text(attachment?.name ?? "")
        .lineLimit(1)
      Spacer(minLength: 4)
      Button("添付を外す", icon: .xmark) {
        InteractionFeedback.shared.send(.selection)
        attachment = nil
      }
      .labelStyle(.iconOnly)
      .frame(width: 44, height: 44)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var attachmentMenu: some View {
    Menu {
      Button("連携サービス…", icon: .plugsConnected) { isIntegrationsPresented = true }
      Divider()
      Button("写真を選択…", icon: .photo) {
        InteractionFeedback.shared.send(.tap)
        isPhotoPickerPresented = true
      }
      Button("音声を選択…", icon: .waveform) {
        InteractionFeedback.shared.send(.tap)
        isAudioImporterPresented = true
      }
      Button("ファイルを選択…", icon: .doc) {
        InteractionFeedback.shared.send(.tap)
        isImporterPresented = true
      }
    } label: {
      Image(icon: .paperclip)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .labelStyle(.iconOnly)
    // A menu tints its label with the accent; the attach glyph stays in the
    // label color like the rest of the composer.
    .tint(.primary)
    .accessibilityLabel("添付を追加")
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
          ArtworkIcon(artwork: .voiceInput, size: 20)
        } else {
          Image(icon: actionSymbol)
        }
      }
        .font(.body.weight(.semibold))
        .foregroundStyle(MemoraPalette.actionLabel)
        .symbolEffect(.pulse, isActive: !reduceMotion && (speechInput.isListening || isBusy))
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        .frame(width: 36, height: 36)
        .background(Circle().fill(MemoraPalette.action))
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
    do {
      guard let sourceURL = try result.get().first else { return }
      attachment = try model.importAIAttachment(from: sourceURL)
    } catch {
      importErrorMessage = "ファイルを添付できませんでした。もう一度お試しください。"
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
