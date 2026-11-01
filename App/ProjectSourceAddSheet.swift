import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSourceAddSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var projectID: UUID?
  @State private var text = ""
  @State private var title = ""
  @State private var photos: [PhotosPickerItem] = []
  @State private var isSelectingPhotos = false
  @State private var photoContext: LocalImportContext?
  @State private var fileContext: LocalImportContext?
  @State private var isImportingFiles = false
  @State private var isMovingRecords = false
  @State private var isSaving = false
  @State private var failure: String?
  @State private var partitionRequest: PDFSourcePartitionRequest?
  @State private var showsPartition = false
  @State private var partitionRemainingURLs: [URL] = []
  private var draftKey: String { "workspace.newNote.\(projectID?.uuidString ?? "library")" }

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          TextEditor(text: $text)
            .frame(minHeight: 150)
            .accessibilityLabel("リンクまたはメモ")
            .accessibilityIdentifier("source.content")
          DisclosureGroup("タイトルを付ける") {
            TextField("タイトル", text: $title).accessibilityLabel("タイトル")
          }
        } header: {
          Text("リンクまたはメモを貼り付け")
        } footer: {
          Text(projectID.flatMap { model.space(id: $0)?.name }.map { "保存先：" + $0 } ?? "ライブラリに保存します")
        }
        Section {
          Button("ファイルを追加", icon: .doc) {
            fileContext = LocalImportContext(projectID: projectID, in: model)
            guard fileContext != nil else { failure = "保存先を確認して開き直してください。"; return }
            isImportingFiles = true
          }
          Button("写真を追加", icon: .photo) {
            photoContext = LocalImportContext(projectID: projectID, in: model)
            guard photoContext != nil else { failure = "保存先を確認して開き直してください。"; return }
            isSelectingPhotos = true
          }
          if projectID != nil {
            Button("既存記録を移動", icon: .folder) { isMovingRecords = true }
          }
        }
        if let failure {
          Section { Text(failure).font(.subheadline).foregroundStyle(MemoraPalette.danger) }
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .disabled(isSaving || model.isRestoring || model.isStoreProtected || model.currentTeamID != nil)
      .navigationTitle("資料を追加")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("追加") { saveText() }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            .accessibilityIdentifier("source.add")
        }
      }
      .onAppear {
        text = DraftStore.load(draftKey) ?? ""
        title = DraftStore.load(draftKey + ".title") ?? ""
      }
      .onChange(of: text) { _, value in DraftStore.save(value, key: draftKey) }
      .onChange(of: title) { _, value in DraftStore.save(value, key: draftKey + ".title") }
      .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
        switch result {
        case .success(let urls):
          importFiles(urls)
        case .failure(let error): failure = error.localizedDescription
        }
      }
      .photosPicker(isPresented: $isSelectingPhotos, selection: $photos, maxSelectionCount: 6, matching: .images)
      .onChange(of: photos) { _, items in
        guard !items.isEmpty else { return }
        let context = photoContext
        perform {
          defer { photos = [] }
          guard let context, context.isCurrent(in: model) else { return false }
          for item in items {
            guard try await model.importProjectSource(title: "写真", context: context, presentsErrorsLocally: true, waitsForPreparation: false, load: {
              try await item.loadTransferable(type: ProjectPhotoTransfer.self)?.receipt
            }) != nil else { return false }
          }
          return true
        }
      }
      .sheet(isPresented: $isMovingRecords) {
        if let projectID { ProjectFilePickerSheet(spaceID: projectID) }
      }
      .navigationDestination(isPresented: $showsPartition) {
        if let partitionRequest {
          PDFSourcePartitionSheet(request: partitionRequest, isPresentedAsSheet: false) { finishPartition() }
        }
      }
      .tint(MemoraPalette.textPrimary)
    }
  }

  private func importFiles(_ urls: [URL]) {
    guard !isSaving, let context = fileContext, context.isCurrent(in: model) else { return }
    isSaving = true
    failure = nil
    Task { @MainActor in
      defer { isSaving = false }
      do {
        let selected = Array(urls.prefix(10))
        for (index, url) in selected.enumerated() {
          guard context.isCurrent(in: model) else { throw ProjectSourceFiles.Failure.invalidFile }
          do {
            guard try await model.importProjectFile(url, projectID: projectID, importContext: context,
              presentsErrorsLocally: true, waitsForPreparation: false) != nil else {
              failure = model.persistenceFailureMessage ?? "保存できませんでした。保存先を確認して再試行してください。"
              return
            }
          } catch ProjectSourceFiles.Failure.tooLarge where SourceIntake.kind(for: url) == .pdf {
            guard context.isCurrent(in: model) else { return }
            partitionRequest = PDFSourcePartitionRequest(url: url, context: context)
            partitionRemainingURLs = Array(selected.dropFirst(index + 1))
            showsPartition = true
            return
          }
        }
        if !urls.isEmpty { dismiss() }
      } catch { failure = error.localizedDescription }
    }
  }

  private func finishPartition() {
    let remaining = partitionRemainingURLs
    partitionRemainingURLs = []
    showsPartition = false
    if remaining.isEmpty { dismiss() }
    else { importFiles(remaining) }
  }

  private func saveText() {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    perform {
      let id: UUID?
      if let url = URL(string: input), url.scheme != nil, !input.contains(where: \.isWhitespace) {
        id = try model.handlingPersistenceFailureLocally { try model.addProjectLink(input, projectID: projectID) }
      } else {
        id = try await model.addProjectNote(title: title, text: input, projectID: projectID, presentsErrorsLocally: true)
        if let id { Task { await model.summarizeProjectSource(id) } }
      }
      guard id != nil else { return false }
      DraftStore.clear(draftKey); DraftStore.clear(draftKey + ".title")
      return true
    }
  }

  private func perform(_ operation: @escaping @MainActor () async throws -> Bool) {
    guard !isSaving else { return }
    isSaving = true; failure = nil
    Task { @MainActor in
      defer { isSaving = false }
      do {
        if try await operation() { dismiss() }
        else { failure = model.persistenceFailureMessage ?? "保存できませんでした。保存先を確認して再試行してください。" }
      } catch { failure = error.localizedDescription }
    }
  }
}
