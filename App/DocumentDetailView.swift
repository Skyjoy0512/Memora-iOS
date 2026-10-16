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
  @State private var isDeleteConfirmationPresented = false
  @State private var shareItems: [Any] = []
  @State private var isSharing = false
  @State private var exportErrorMessage: String?
  @State private var citedRecord: AIChatSource?
  @State private var sourceErrorMessage: String?

  var body: some View {
    Group {
      if let document = model.document(id: documentID) {
        content(document)
      } else {
        ContentUnavailableView("資料が見つかりません", icon: .docQuestionmark, description: Text("削除された可能性があります。"))
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { model.markDocumentOpened(documentID) }
  }

  private func content(_ document: MemoraDocument) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header(document)
          if let name = document.artifactFileReference, let url = ProjectSourceFiles.resolve(name) {
            HStack {
              Button("生成ファイルを確認", icon: .docText) { artifactPreview = url }
              ShareLink(item: url) { Label("保存・共有", icon: .squareAndArrowUp) }
            }
            .buttonStyle(.borderless)
          }

          switch document.kind {
          case .document:
            InlineMarkdownEditor(
              text: document.markdown,
              placeholder: "タップして入力",
              rendersBlocks: true,
              draftKey: "document.\(document.id).body",
              onCommit: { model.updateDocument(document.id, title: document.title, body: $0) }
            )
            .environment(\.openURL, OpenURLAction { url in
              guard url.scheme == "memora", url.host == "meeting",
                    let meetingID = UUID(uuidString: url.lastPathComponent) else { return .systemAction }
              if let meeting = model.meeting(id: meetingID) {
                citedRecord = AIChatSource(meetingID: meeting.id, title: meeting.title)
              } else {
                sourceErrorMessage = model.trashedRecords.contains(where: { $0.meeting.id == meetingID })
                  ? "この記録は「最近削除した項目」にあります。設定から元に戻すと開けます。"
                  : "この端末に元の記録はありません。リンクは記録のある端末でのみ開けます。"
              }
              return .handled
            })
          case .slides:
            slideList(document)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
      }
      .scrollFocusedEditorAboveKeyboard(in: proxy)
    }
    .contentMargins(.bottom, showsCloseButton ? 0 : model.bottomContentClearance, for: .scrollContent)
    .navigationTitle(document.displayTitle)
    .toolbar {
      if showsCloseButton {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }

      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          if document.kind == .document {
            Button("Wordで共有", icon: .docRichtext) { share(document, as: .word) }
          }
          Button("PDFで共有", icon: .docRichtext) { share(document, as: .pdf) }
          if document.kind == .slides {
            Button("PowerPointで共有", icon: .rectangleOnRectangleAngled) { share(document, as: .powerPoint) }
          }
          Button("テキストで共有", icon: .textAlignleft) { share(document, as: .text) }
        } label: {
          ToolbarActionLabel("共有", icon: .squareAndArrowUp)
        }
      }

      ToolbarActionGap()
      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          Button("編集", icon: .pencil) { isEditing = true }
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
    .sheet(isPresented: $isSharing, onDismiss: cleanUpShare) {
      ActivityView(items: shareItems, onComplete: cleanUpShare)
    }
    .sheet(item: $citedRecord) { source in
      NavigationStack {
        MeetingDetailView(meetingID: source.meetingID, showsLocalPlaybackBar: true)
      }
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
        model.deleteDocument(document.id)
        dismiss()
      }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("削除した資料は元に戻せません。")
    }
    .alert("書き出せませんでした", isPresented: Binding(
      get: { exportErrorMessage != nil },
      set: { if !$0 { exportErrorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(exportErrorMessage ?? "")
    }
  }

  private func header(_ document: MemoraDocument) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(document.displayTitle)
        .font(.title2.bold())
      Label(caption(document), icon: document.kind.symbol)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private func caption(_ document: MemoraDocument) -> String {
    var parts = [document.weekStart == nil ? document.kind.label : "週報", document.updatedAt.formatted(date: .abbreviated, time: .shortened)]
    if let spaceID = document.spaceID, let space = model.space(id: spaceID) {
      parts.append(space.name)
    }
    return parts.joined(separator: " · ")
  }

  private func slideList(_ document: MemoraDocument) -> some View {
    LazyVStack(alignment: .leading, spacing: 18) {
      ForEach(Array(document.slides.enumerated()), id: \.element.id) { index, slide in
        VStack(alignment: .leading, spacing: 8) {
          SlideView(slide: slide)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(index + 1)")
              .font(.caption.weight(.semibold).monospacedDigit())
              .foregroundStyle(.secondary)
            if !slide.notes.isEmpty {
              Text(slide.notes)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }

  private enum ShareFormat {
    case pdf
    case word
    case powerPoint
    case text
  }

  private func share(_ document: MemoraDocument, as format: ShareFormat) {
    do {
      switch format {
      case .word:
        shareItems = [try DOCXWriter.write(document)]
      case .pdf:
        shareItems = [try DocumentPDF.write(document)]
      case .powerPoint:
        shareItems = [try PPTXWriter.write(document)]
      case .text:
        shareItems = [document.plainText]
      }
      isSharing = true
    } catch {
      exportErrorMessage = "ファイルを作れませんでした。もう一度お試しください。"
    }
  }

  /// Removes the temporary export once the share sheet is done with it.
  private func cleanUpShare() {
    for case let url as URL in shareItems where url.isFileURL {
      try? FileManager.default.removeItem(at: url)
    }
    shareItems = []
  }
}
