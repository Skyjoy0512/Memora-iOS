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
  var onSubmit: () -> Void
  var focusChanged: ((Bool) -> Void)?

  @State private var speechInput = SpeechInputService()
  @State private var isImporterPresented = false
  @State private var isAudioImporterPresented = false
  @State private var isPhotoPickerPresented = false
  @State private var photoItem: PhotosPickerItem?
  @State private var importErrorMessage: String?
  @FocusState private var isFieldFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let attachment {
        HStack(spacing: 8) {
          Image(systemName: "paperclip")
          Text(attachment.name)
            .lineLimit(1)
          Spacer(minLength: 4)
          Button("添付を外す", systemImage: "xmark") {
            self.attachment = nil
          }
          .labelStyle(.iconOnly)
          .frame(width: 36, height: 36)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)

        Divider()
          .padding(.horizontal, 14)
          .padding(.top, 4)
      }

      HStack(alignment: .bottom, spacing: 2) {
        Menu {
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
          Label("添付を追加", systemImage: "plus")
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.medium))
        .frame(width: 44, height: 48)
        .contentShape(Circle())

        TextField(placeholder, text: $text, axis: .vertical)
          .font(.body)
          .lineLimit(1...5)
          .submitLabel(.send)
          .onSubmit(submit)
          .focused($isFieldFocused)
          .padding(.vertical, 13)

        Button(speechInput.isListening ? "音声入力を停止" : "音声で入力", systemImage: speechInput.isListening ? "waveform" : "mic") {
          Task {
            await speechInput.toggle { transcript in
              text = transcript
            }
          }
        }
        .labelStyle(.iconOnly)
        .font(.body)
        .frame(width: 44, height: 48)
        .foregroundStyle(speechInput.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        .symbolEffect(.variableColor.iterative, isActive: speechInput.isListening)
        .contentTransition(.symbolEffect(.replace))
        .contentShape(Circle())

        Button("送信", systemImage: "arrow.up") {
          submit()
        }
        .labelStyle(.iconOnly)
        .font(.body.weight(.semibold))
        .frame(width: 42, height: 42)
        .foregroundStyle(canSend ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.tertiary))
        .background(canSend ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Circle())
        .contentShape(Circle())
        .disabled(!canSend)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
      }
      .padding(.leading, 4)
    }
    .memoraGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), interactive: true)
    .overlay {
      MemoraBorderBeam(cornerRadius: 28, strength: 0.7)
    }
    .animation(reduceMotion ? nil : MemoraMotion.control, value: attachment)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: canSend)
    .animation(reduceMotion ? nil : MemoraMotion.control, value: speechInput.isListening)
    .sensoryFeedback(.impact(weight: .light), trigger: speechInput.isListening)
    .onChange(of: isFieldFocused) { _, focused in
      focusChanged?(focused)
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

  private var canSend: Bool {
    (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil) && !isBusy
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

  private func submit() {
    guard canSend else { return }
    speechInput.stop()
    isFieldFocused = false
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
    defer { photoItem = nil }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
      attachment = try model.importAIPhoto(data: data, fileExtension: fileExtension)
    } catch {
      importErrorMessage = "写真を添付できませんでした。もう一度お試しください。"
    }
  }
}
