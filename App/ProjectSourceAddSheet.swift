import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ProjectSourceAddSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var projectID: UUID?
  /// Retains the old draft preference; both entry points use the same editor.
  var isMemo = false
  @State private var saveContext: LocalImportContext?
  @State private var hasLoadedDraft = false
  @State private var isDraftReady = false
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
  @State private var importedSourceIDs: [UUID] = []
  @State private var activeDraftKey: String?
  @State private var availableDraftKeys: [String] = []
  @ScaledMetric(relativeTo: .body) private var titleFieldMinHeight: CGFloat = 24
  @FocusState private var isNoteFocused: Bool
  private var preferredDraftKey: String { "workspace.\(isMemo ? "newMemo" : "newNote").\(projectID?.uuidString ?? "library")" }
  private var draftKey: String { activeDraftKey ?? preferredDraftKey }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
          pageHeader
          sourceAttachments
          notesContent
          if let failure { Text(failure).font(.subheadline).foregroundStyle(MemoraPalette.danger) }
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.sm)
        .padding(.bottom, MemoraSpacing.xxl)
        .frame(maxWidth: .infinity)
      }
      .background(MemoraPalette.background)
      .scrollDismissesKeyboard(.interactively)
      .disabled(!isDraftReady || isSaving || model.isRestoring || model.isStoreProtected || model.currentTeamID != nil)
      .navigationTitle("新しいノート")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("保存", icon: .checkmark) { saveText() }
            .disabled(!isDraftReady || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            .accessibilityIdentifier("source.add")
        }
        if availableDraftKeys.count > 1 {
          ToolbarItem(placement: .topBarTrailing) {
            Menu("下書き", icon: .clockArrowCirclepath) {
              ForEach(availableDraftKeys, id: \.self) { key in
                Button(key.contains("newMemo") ? "メモの下書き" : "資料の下書き") { switchDraft(to: key) }
              }
            }
          }
        }
      }
      .onAppear {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true
        guard let context = LocalImportContext(projectID: projectID, in: model) else {
          failure = "この保存先では編集できません。画面を開き直してください。"
          return
        }
        saveContext = context
        restoreDrafts()
      }
      .onChange(of: text) { _, value in
        if isDraftReady, saveContext?.isCurrent(in: model) == true { DraftStore.save(value, key: draftKey) }
      }
      .onChange(of: title) { _, value in
        if isDraftReady, saveContext?.isCurrent(in: model) == true { DraftStore.save(value, key: draftKey + ".title") }
      }
      .interactiveDismissDisabled(isSaving)
      .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
        switch result {
        case .success(let urls):
          importFiles(urls)
        case .failure(let error):
          if (error as NSError).code != NSUserCancelledError { failure = error.localizedDescription }
        }
      }
      .photosPicker(isPresented: $isSelectingPhotos, selection: $photos, maxSelectionCount: 6, matching: .images)
      .onChange(of: photos) { _, items in
        guard !items.isEmpty else { return }
        let context = photoContext
        perform(dismissOnSuccess: false) {
          defer { photos = [] }
          guard let context, context.isCurrent(in: model) else { return false }
          for item in items {
            guard let id = try await model.importProjectSource(title: "写真", context: context, presentsErrorsLocally: true, waitsForPreparation: false, load: {
              try await item.loadTransferable(type: ProjectPhotoTransfer.self)?.receipt
            }) else { return false }
            rememberSources([id])
          }
          return true
        }
      }
      .sheet(isPresented: $isMovingRecords) {
        if let projectID { ProjectFilePickerSheet(spaceID: projectID) }
      }
      .tint(MemoraPalette.textPrimary)
    }
    .presentationDetents([.large])
  }

  private var pageHeader: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Text("タイトル（任意）")
        .font(MemoraTypography.sectionHeading)
        .accessibilityHidden(true)
      TextField("", text: $title, prompt: Text("例：会議メモ")
        .foregroundStyle(MemoraPalette.textSecondary))
        .font(MemoraTypography.body)
        .textFieldStyle(.plain)
        .frame(minHeight: titleFieldMinHeight, alignment: .leading)
        .submitLabel(.next)
        .onSubmit { isNoteFocused = true }
        .accessibilityLabel("タイトル")
        .accessibilityHint("任意項目")
      Text(projectID.flatMap { model.space(id: $0)?.name }.map { "保存先：" + $0 } ?? "ライブラリに保存します")
        .font(MemoraTypography.secondary)
        .foregroundStyle(MemoraPalette.textSecondary)
    }
  }

  private var notesContent: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Text("ノート").font(MemoraTypography.sectionHeading)
      MarkdownEditorField(markdown: $text, font: .body, minHeight: 200, isFocused: $isNoteFocused)
        .accessibilityLabel("ノート本文")
        .accessibilityIdentifier("source.content")
        .overlay(alignment: .topLeading) {
          if text.isEmpty && !isNoteFocused {
            Text("メモを書くか、リンクを貼り付け")
              .font(.body).foregroundStyle(MemoraPalette.textSecondary)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
    }
  }

  private var sourceAttachments: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Menu {
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
      } label: {
        Label("資料を追加", icon: .paperclip)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      addedSources
    }
  }

  private var addedSources: some View {
    let sources = importedSourceIDs.compactMap { model.source(id: $0) }
    return VStack(alignment: .leading, spacing: 14) {
      if !sources.isEmpty {
        Text("追加した資料は保存済みです")
          .font(.caption).foregroundStyle(.secondary)
        ForEach(sources) { source in
          NavigationLink { ProjectSourceDetailView(sourceID: source.id) } label: {
            ProjectSourceRow(source: source)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func restoreDrafts() {
    let otherKey = "workspace.\(isMemo ? "newNote" : "newMemo").\(projectID?.uuidString ?? "library")"
    var drafts: [(key: String, text: String, title: String)] = []
    for key in [preferredDraftKey, otherKey] {
      let body = DraftStore.read(key), heading = DraftStore.read(key + ".title")
      guard body != .unreadable, heading != .unreadable else {
        failure = "下書きを読み込めませんでした。元の下書きは変更していません。画面を開き直してお試しください。"
        return
      }
      drafts.append((key, body.text ?? "", heading.text ?? ""))
    }
    let pending = drafts.filter { !$0.text.isEmpty || !$0.title.isEmpty }
    availableDraftKeys = pending.map(\.key)
    let restored = pending.first ?? drafts[0]
    activeDraftKey = restored.key
    text = restored.text
    title = restored.title
    isDraftReady = true
  }

  private func switchDraft(to key: String) {
    guard isDraftReady, !isSaving, saveContext?.isCurrent(in: model) == true, key != draftKey else { return }
    isNoteFocused = false
    do {
      try DraftStore.saveAndWait(text, key: draftKey)
      try DraftStore.saveAndWait(title, key: draftKey + ".title")
      let body = DraftStore.read(key), heading = DraftStore.read(key + ".title")
      guard body != .unreadable, heading != .unreadable else { throw CocoaError(.fileReadCorruptFile) }
      activeDraftKey = key
      text = body.text ?? ""
      title = heading.text ?? ""
      failure = nil
    } catch { failure = "下書きを切り替えられませんでした。編集中の内容は保持しています。" }
  }

  private func rememberSources(_ ids: [UUID]) {
    for id in ids where !importedSourceIDs.contains(id) { importedSourceIDs.append(id) }
  }

  private func importFiles(_ urls: [URL]) {
    guard !isSaving, let context = fileContext, context.isCurrent(in: model) else { return }
    isSaving = true
    failure = nil
    Task { @MainActor in
      defer { isSaving = false }
      do {
        guard urls.count <= 10 else { failure = "一度に追加できるファイルは10件です。"; return }
        for url in urls {
          guard context.isCurrent(in: model) else { throw ProjectSourceFiles.Failure.invalidFile }
          guard let ids = try await model.importInformationSources(url, context: context, presentsErrorsLocally: true),
                !ids.isEmpty else {
            failure = model.persistenceFailureMessage ?? "保存できませんでした。保存先を確認して再試行してください。"
            return
          }
          rememberSources(ids)
        }
      } catch { failure = error.localizedDescription }
    }
  }

  private func saveText() {
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isDraftReady, let context = saveContext, context.isCurrent(in: model) else {
      failure = "保存先が変更されました。画面を開き直してください。"
      return
    }
    perform {
      guard context.isCurrent(in: model) else { return false }
      let draftKeys = [DraftStore.storageKey(for: draftKey), DraftStore.storageKey(for: draftKey + ".title")]
      let id: UUID?
      if let url = URL(string: input), url.scheme != nil, !input.contains(where: \.isWhitespace) {
        id = try model.handlingPersistenceFailureLocally { try model.addProjectLink(input, projectID: projectID, removing: draftKeys) }
      } else {
        id = try await model.addProjectNote(title: title, text: input, projectID: projectID, presentsErrorsLocally: true,
          removing: draftKeys, attachedSourceIDs: importedSourceIDs)
        if let id { Task { await model.summarizeProjectSource(id) } }
      }
      guard id != nil else { return false }
      return true
    }
  }

  private func perform(dismissOnSuccess: Bool = true, _ operation: @escaping @MainActor () async throws -> Bool) {
    guard !isSaving else { return }
    isSaving = true; failure = nil
    Task { @MainActor in
      defer { isSaving = false }
      do {
        if try await operation() { if dismissOnSuccess { dismiss() } }
        else { failure = model.persistenceFailureMessage ?? "保存できませんでした。保存先を確認して再試行してください。" }
      } catch { failure = error.localizedDescription }
    }
  }
}
