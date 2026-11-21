import SwiftUI
import QuickLook

/// Reads a document or flips through its slides, and shares it as PDF,
/// PowerPoint or text.
struct DocumentDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var documentID: UUID
  /// Shown with a close button when it is opened as a sheet from Ask AI.
  var showsCloseButton = false

  @State private var artifactPreview: URL?
  @State private var isEditing = false
  @State private var presentationEditRequest: PresentationEditRequest?
  @State private var isDeleteConfirmationPresented = false
  @State private var shareItems: [Any] = []
  @State private var isSharing = false
  @State private var exportErrorMessage: String?
  @State private var citedSource: ArtifactSourceTarget?
  @State private var sourceErrorMessage: String?
  @State private var deleteError = false
  @State private var pdfExport = DocumentPDFExportSession()

  var body: some View {
    Group {
      if let document = model.document(id: documentID) {
        content(document)
      } else {
        ContentUnavailableView("資料が見つかりません", icon: .docQuestionmark, description: Text("削除された可能性があります。"))
      }
    }
    .disabled(pdfExport.isRunning)
    .accessibilityHidden(pdfExport.isRunning)
    .overlay {
      if let progress = pdfExport.progress {
        ZStack {
          Color.black.opacity(0.08).ignoresSafeArea().accessibilityHidden(true)
          DocumentPDFExportProgressView(progress: progress) { pdfExport.cancel() }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { model.markDocumentOpened(documentID) }
    .onDisappear { pdfExport.cancel() }
  }

  private func content(_ document: MemoraDocument) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header(document)
          if let name = document.artifactFileReference, let url = ProjectSourceFiles.resolve(name) {
            DocumentArtifactFileView(document: document, url: url) { artifactPreview = url }
          }
          if document.kind == .slides, document.companyTemplateID != nil {
            CompanyPresentationExportView(model: model, document: document)
            CompanyPresentationPreviewButton(model: model, document: document)
          }
          if let revisions = document.artifactHistory, !revisions.isEmpty {
            DocumentArtifactHistoryView(revisions: revisions, preview: previewRevision, share: shareRevision)
          }

          ArtifactSourcesView(provenance: document.provenance, meetingIDs: document.sourceRecordIDs ?? [],
            projectFileIDs: document.sourceProjectFileIDs ?? [])
          switch document.kind {
          case .document:
            InlineMarkdownEditor(
              text: document.markdown,
              placeholder: "タップして入力",
              rendersBlocks: true,
              draftKey: "document.\(document.id).body",
              animatesReading: true,
              onCommit: { model.updateDocument(document.id, title: document.title, body: $0, expectedUpdatedAt: document.updatedAt) }
            )
            .environment(\.openURL, OpenURLAction { url in
              guard url.scheme?.lowercased() == "memora" else { return .systemAction }
              if let target = model.documentCitationTarget(for: url, document: document) {
                citedSource = target
              } else {
                sourceErrorMessage = "この資料の出典を確認できません。元の情報とワークスペースを確認してください。"
              }
              return .handled
            })
          case .slides:
            PresentationQualityView(document: document) { id in
              presentationEditRequest = PresentationEditRequest(document: document, initialSlideID: id)
            }
            DocumentSlidesView(document: document)
          }
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.vertical, MemoraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .center)
      }
      .scrollFocusedEditorAboveKeyboard(in: proxy)
    }
    .contentMargins(.bottom, showsCloseButton ? 0 : model.bottomContentClearance, for: .scrollContent)
    .background(MemoraPalette.background)
    .navigationTitle("資料")
    .toolbar {
      if showsCloseButton {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }

      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          if document.kind == .document {
            Button(document.companyTemplateID != nil && document.hasOutdatedArtifact ? "編集前のWordを共有" : "Wordで共有", icon: .docRichtext) { share(document, as: .word) }
          }
          if document.companyTemplateID == nil {
            Button("PDFで共有", icon: .docRichtext) { share(document, as: .pdf) }
          } else {
            Button("PDFで共有（会社書式は未対応）", icon: .docRichtext) {}
              .disabled(true)
          }
          if document.kind == .slides {
            Button(document.companyTemplateID != nil && document.hasOutdatedArtifact ? "編集前のPowerPointを共有" : "PowerPointで共有", icon: .rectangleOnRectangleAngled) { share(document, as: .powerPoint) }
          }
          Button("テキストで共有", icon: .textAlignleft) { share(document, as: .text) }
        } label: {
          ToolbarActionLabel("共有", icon: .squareAndArrowUp)
        }
      }

      ToolbarActionGap()
      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          Button("編集", icon: .pencil) {
            if document.kind == .slides { presentationEditRequest = PresentationEditRequest(document: document) }
            else { isEditing = true }
          }
          Button("削除", icon: .trash, role: .destructive) { isDeleteConfirmationPresented = true }
        } label: {
          ToolbarActionLabel("その他", icon: .ellipsis)
        }
      }
    }
    .quickLookPreview($artifactPreview)
    .sheet(isPresented: $isEditing) {
      DocumentEditSheet(document: document)
    }
    .sheet(item: $presentationEditRequest) { request in
      PresentationEditorView(document: request.document, initialSlideID: request.initialSlideID)
    }
    .sheet(isPresented: $isSharing, onDismiss: cleanUpShare) {
      ActivityView(items: shareItems, onComplete: cleanUpShare)
    }
    .sheet(item: $citedSource) { target in
      ArtifactSourceDetailView(target: target, workspaceID: document.provenance?.workspaceID)
    }
    .alert("元の記録を開けません", isPresented: Binding(
      get: { sourceErrorMessage != nil },
      set: { if !$0 { sourceErrorMessage = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(sourceErrorMessage ?? "")
    }
    .confirmationDialog("この\(document.kind.label)を削除しますか？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        if model.deleteDocument(document.id) { dismiss() }
        else { deleteError = true }
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text(document.artifactHistory?.isEmpty == false
        ? "以前のファイルも削除され、元に戻せません。会社テンプレートの原本は残ります。"
        : "削除した資料は元に戻せません。")
    }
    .alert("削除できませんでした", isPresented: $deleteError) {
      Button("閉じる", role: .cancel) {}
    } message: { Text("資料は残っています。保存先を確認して、もう一度お試しください。") }
    .alert("書き出せませんでした", isPresented: Binding(
      get: { exportErrorMessage != nil },
      set: { if !$0 { exportErrorMessage = nil } }
    )) {
      Button("閉じる", role: .cancel) {}
    } message: {
      Text(exportErrorMessage ?? "")
    }
  }

  private func header(_ document: MemoraDocument) -> some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Text(document.displayTitle)
        .font(MemoraTypography.screenTitle)
        .memoraTextReveal()
      Text(caption(document))
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private func caption(_ document: MemoraDocument) -> String {
    var parts = [document.weekStart == nil ? document.kind.label : "週報", document.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP")))]
    if let spaceID = document.spaceID, let space = model.space(id: spaceID) {
      parts.append(space.name)
    }
    return parts.joined(separator: " · ")
  }

  private enum ShareFormat {
    case pdf
    case word
    case powerPoint
    case text
  }

  private func share(_ document: MemoraDocument, as format: ShareFormat) {
    if format == .pdf {
      let workspace = model.currentTeamID, generation = model.aiWorkspaceGeneration
      pdfExport.start(document: document, isCurrent: {
        model.currentTeamID == workspace && model.aiWorkspaceGeneration == generation
          && !model.isRestoring && !model.isStoreProtected && model.document(id: document.id) == document
      }, completed: { url in
        shareItems = [url]
        isSharing = true
      }, failed: { exportErrorMessage = $0 })
      return
    }
    do {
      switch format {
      case .word:
        shareItems = [try originalArtifact(document, suffix: "docx") ?? DOCXWriter.write(document)]
      case .pdf:
        return
      case .powerPoint:
        if document.companyTemplateID == nil && !document.slides.isEmpty {
          // Stored standard exports may predate the current pagination policy.
          shareItems = [try PPTXWriter.write(document)]
        } else {
          shareItems = [try originalArtifact(document, suffix: "pptx") ?? PPTXWriter.write(document)]
        }
      case .text:
        shareItems = [document.plainText]
      }
      isSharing = true
    } catch let error as CocoaError where error.code == .fileNoSuchFile && document.companyTemplateID != nil {
      exportErrorMessage = "会社書式のファイルが見つかりません。共有メニューからテキストで共有できます。"
    } catch {
      exportErrorMessage = error.localizedDescription
    }
  }

  private func originalArtifact(_ document: MemoraDocument, suffix: String) throws -> URL? {
    if document.hasOutdatedArtifact && document.companyTemplateID == nil { return nil }
    if document.companyTemplateID != nil {
      guard document.artifactFormat?.lowercased() == suffix, let name = document.artifactFileReference,
            let source = ProjectSourceFiles.resolve(name) else { throw CocoaError(.fileNoSuchFile) }
      return try ArtifactExportFile.copy(source, preferredName: document.exportFileName, suffix: suffix)
    }
    guard document.artifactFormat?.lowercased() == suffix, let name = document.artifactFileReference,
          let source = ProjectSourceFiles.resolve(name) else { return nil }
    return try ArtifactExportFile.copy(source, preferredName: document.exportFileName, suffix: suffix)
  }

  private func revisionURL(_ revision: DocumentArtifactRevision) throws -> URL {
    guard model.document(id: documentID)?.artifactHistory?.contains(revision) == true, revision.isValid,
          let url = ProjectSourceFiles.resolve(revision.fileReference),
          let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
          attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw CocoaError(.fileNoSuchFile) }
    return url
  }

  private func previewRevision(_ revision: DocumentArtifactRevision) {
    do { artifactPreview = try revisionURL(revision) }
    catch { exportErrorMessage = "以前のファイルが見つかりません。バックアップを確認してください。" }
  }

  private func shareRevision(_ revision: DocumentArtifactRevision) {
    do {
      let source = try revisionURL(revision)
      let name = (model.document(id: documentID)?.exportFileName ?? "資料") + "-v\(revision.contentRevision)"
      shareItems = [try ArtifactExportFile.copy(source, preferredName: name, suffix: revision.format.rawValue.lowercased())]
      isSharing = true
    } catch { exportErrorMessage = error.localizedDescription }
  }

  /// Removes the temporary export once the share sheet is done with it.
  private func cleanUpShare() {
    ArtifactExportFile.removeTemporary(shareItems)
    shareItems = []
  }
}
