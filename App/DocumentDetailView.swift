import SwiftUI

/// Reads a document or flips through its slides, and shares it as PDF,
/// PowerPoint or text.
struct DocumentDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var documentID: UUID
  /// Shown with a close button when it is opened as a sheet from Ask AI.
  var showsCloseButton = false

  @State private var isEditing = false
  @State private var isDeleteConfirmationPresented = false
  @State private var shareItems: [Any] = []
  @State private var isSharing = false
  @State private var exportErrorMessage: String?

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
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header(document)

        switch document.kind {
        case .document:
          MarkdownDocumentView(markdown: document.markdown, isLazy: true)
            .textSelection(.enabled)
        case .slides:
          slideList(document)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
    }
    .contentMargins(.bottom, showsCloseButton ? 0 : model.bottomContentClearance, for: .scrollContent)
    .navigationTitle(document.displayTitle)
    .toolbar {
      if showsCloseButton {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("PDFで共有", icon: .docRichtext) { share(document, as: .pdf) }
          if document.kind == .slides {
            Button("PowerPointで共有", icon: .rectangleOnRectangleAngled) { share(document, as: .powerPoint) }
          }
          Button("テキストで共有", icon: .textAlignleft) { share(document, as: .text) }
        } label: {
          Label("共有", icon: .squareAndArrowUp)
            .labelStyle(.iconOnly)
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("編集", icon: .pencil) { isEditing = true }
          Button("削除", icon: .trash, role: .destructive) { isDeleteConfirmationPresented = true }
        } label: {
          Label("その他", icon: .ellipsis)
            .labelStyle(.iconOnly)
        }
      }
    }
    .sheet(isPresented: $isEditing) {
      DocumentEditSheet(document: document)
    }
    .sheet(isPresented: $isSharing, onDismiss: cleanUpShare) {
      ActivityView(items: shareItems, onComplete: cleanUpShare)
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
    case powerPoint
    case text
  }

  private func share(_ document: MemoraDocument, as format: ShareFormat) {
    do {
      switch format {
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
