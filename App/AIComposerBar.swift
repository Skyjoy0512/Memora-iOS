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
  /// Keeps the keyboard up after sending, so a chat can continue.
  var keepsFocusAfterSubmit = false
  /// Focuses the field when it appears, used when Ask AI opens to an empty chat.
  var autofocus = false
  /// Returns true when the send was accepted. Only then does the composer clear
  /// what was typed, so a refused send keeps the text and the attachment.
  var onSubmit: (AIAttachment?) -> Bool
  var focusChanged: ((Bool) -> Void)?

  @State private var speechInput = SpeechInputService()
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
    isFieldFocused || hasContent
  }

  private var cornerRadius: CGFloat {
    isExpanded ? 24 : Self.collapsedHeight / 2
  }

  private var textField: some View {
    TextField(placeholder, text: $text, axis: .vertical)
      .font(.body)
      .lineLimit(isExpanded ? 1...6 : 1...1)
      .submitLabel(.send)
      .onSubmit(submit)
      .focused($isFieldFocused)
      .padding(.vertical, 8)
      // The field takes the width it needs and grows as text is added; the
      // controls keep their size instead of being pushed out by a long entry.
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
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
          Spacer(minLength: 8)
          actionButton
            .matchedGeometryEffect(id: "action", in: controlsNamespace)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .transition(.opacity)
      }
    }
    .background { listeningBackdrop }
    .memoraGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: true)
    .shadow(color: .black.opacity(speechInput.isListening ? 0.3 : 0.08), radius: 18, y: 8)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: attachment)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: hasContent)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: speechInput.isListening)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: isExpanded)
    .sensoryFeedback(.impact(weight: .light), trigger: speechInput.isListening)
    .onChange(of: isFieldFocused) { _, focused in
      focusChanged?(focused)
    }
    .onChange(of: model.composerDismissRequests) { _, _ in
      isFieldFocused = false
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
      Button("写真を選択…", icon: .photo) {
        isPhotoPickerPresented = true
      }
      Button("音声を選択…", icon: .waveform) {
        isAudioImporterPresented = true
      }
      Button("ファイルを選択…", icon: .doc) {
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

  private var actionButton: some View {
    Button {
      if canSend {
        submit()
      } else if !isBusy {
        toggleSpeechInput()
      }
    } label: {
      Image(icon: actionSymbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .symbolEffect(.pulse, isActive: !reduceMotion && (speechInput.isListening || isBusy))
        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        .frame(width: 36, height: 36)
        .background(Circle().fill(.tint))
        // The circle stays small; the target around it does not.
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isBusy || (!canSend && model.isRecording))
    .accessibilityLabel(actionLabel)
  }

  private var actionSymbol: MemoraIcon {
    if isBusy { return .ellipsis }
    return canSend ? .arrowUp : .waveform
  }

  private var actionLabel: String {
    if canSend { return "送信" }
    if model.isRecording { return "録音中は音声入力を使用できません" }
    return speechInput.isListening ? "音声入力を停止" : "音声で入力"
  }

  private var hasContent: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil
  }

  private var canSend: Bool {
    hasContent && !isBusy
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
    guard canSend else { return }
    speechInput.stop()
    guard onSubmit(attachment) else { return }
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
