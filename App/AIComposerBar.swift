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
  /// Keeps the keyboard up after sending, so a chat can continue. The field is
  /// never focused on its own.
  var keepsFocusAfterSubmit = false
  var onSubmit: () -> Void
  var focusChanged: ((Bool) -> Void)?

  @State private var speechInput = SpeechInputService()
  @State private var isImporterPresented = false
  @State private var isAudioImporterPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var isCameraPresented = false
  @State private var photoItem: PhotosPickerItem?
  @State private var editingPhoto: PhotoEditRequest?
  @State private var importErrorMessage: String?
  @FocusState private var isFieldFocused: Bool

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

      HStack(spacing: 6) {
        attachmentMenu

        TextField(placeholder, text: $text, axis: .vertical)
          .font(.body)
          .lineLimit(1...5)
          .submitLabel(.send)
          .onSubmit(submit)
          .focused($isFieldFocused)
          .padding(.vertical, 8)

        modelMenu
        actionButton
      }
      .padding(.leading, 8)
      .padding(.trailing, 8)
      .padding(.vertical, 6)
    }
    .background { listeningBackdrop }
    .memoraGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), interactive: true)
    .shadow(color: .black.opacity(speechInput.isListening ? 0.3 : 0.08), radius: 18, y: 8)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: attachment)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: hasContent)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: speechInput.isListening)
    .sensoryFeedback(.impact(weight: .light), trigger: speechInput.isListening)
    .onChange(of: isFieldFocused) { _, focused in
      focusChanged?(focused)
    }
    .onChange(of: model.composerDismissRequests) { _, _ in
      isFieldFocused = false
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
    .fullScreenCover(isPresented: $isCameraPresented) {
      CameraCaptureSheet()
    }
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
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
  }

  private var attachmentStrip: some View {
    HStack(spacing: 8) {
      Image(systemName: "paperclip")
      Text(attachment?.name ?? "")
        .lineLimit(1)
      Spacer(minLength: 4)
      Button("添付を外す", systemImage: "xmark") {
        attachment = nil
      }
      .labelStyle(.iconOnly)
      .frame(width: 32, height: 32)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private var attachmentMenu: some View {
    Menu {
      Button("カメラで撮影…", systemImage: "camera") {
        isCameraPresented = true
      }
      Button("写真を選択…", systemImage: "photo") {
        isPhotoPickerPresented = true
      }
      Button("音声を選択…", systemImage: "waveform") {
        isAudioImporterPresented = true
      }
      Button("ファイルを選択…", systemImage: "doc") {
        isImporterPresented = true
      }
    } label: {
      Image(systemName: "paperclip")
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
    .labelStyle(.iconOnly)
    .accessibilityLabel("添付を追加")
  }

  /// Shows the engine that will actually answer, not a separate model label.
  private var modelMenu: some View {
    Menu {
      ForEach(AIEngine.allCases) { option in
        Button {
          model.aiEngine = option
        } label: {
          if option == model.aiEngine {
            Label(option.label, systemImage: "checkmark")
          } else {
            Text(option.label)
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: model.aiEngine.symbol)
          .font(.subheadline)

        Text(model.aiEngine.shortLabel)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)

        Image(systemName: "chevron.down")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .foregroundStyle(.primary)
      .padding(.horizontal, 6)
      .frame(height: 32)
      .contentShape(Rectangle())
    }
    .accessibilityLabel("使用するAIエンジン")
  }

  private var actionButton: some View {
    Button {
      if canSend {
        submit()
      } else if !isBusy {
        toggleSpeechInput()
      }
    } label: {
      Image(systemName: actionSymbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(Color(uiColor: .systemBackground))
        .frame(width: 36, height: 36)
        .background(Circle().fill(.primary))
        .symbolEffect(.variableColor.iterative, isActive: speechInput.isListening)
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.plain)
    .disabled(isBusy)
    .accessibilityLabel(actionLabel)
  }

  private var actionSymbol: String {
    if isBusy { return "ellipsis" }
    return canSend ? "arrow.up" : "waveform"
  }

  private var actionLabel: String {
    if canSend { return "送信" }
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
    Task {
      await speechInput.toggle { transcript in
        text = transcript
      }
    }
  }

  private func submit() {
    guard canSend else { return }
    speechInput.stop()
    // The Ask AI chat keeps the keyboard up for the next turn; a sheet does not.
    isFieldFocused = keepsFocusAfterSubmit
    onSubmit()
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
