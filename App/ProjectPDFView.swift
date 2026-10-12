import SwiftUI
import PDFKit

struct ProjectPDFView: View {
  @Environment(MemoraModel.self) private var model
  var sourceID: UUID
  var page: Int = 1
  @State private var loaded: LoadedProjectPDF?

  var body: some View {
    if let source = model.source(id: sourceID), source.kind == .pdf,
       let name = source.localFileReference, let url = ProjectSourceFiles.resolve(name) {
      Group {
        if let loaded {
          if let document = loaded.document, !document.isLocked,
             let index = ProjectCitationLocation.pageIndex(page, count: document.pageCount) {
            NativeProjectPDF(document: document, pageIndex: index)
          } else {
            ContentUnavailableView("PDFを開けません", icon: .docQuestionmark,
              description: Text("ファイルの状態とページ番号を確認してください。暗号化されたPDFは対応していません。"))
          }
        } else {
          ProgressView("PDFを読み込んでいます")
        }
      }
      .navigationTitle(source.title).navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: model.bottomContentClearance) }
      .task(id: name) {
        loaded = nil
        let result = await Task.detached(priority: .userInitiated) { LoadedProjectPDF(url: url) }.value
        guard !Task.isCancelled, model.source(id: sourceID)?.localFileReference == name else { return }
        loaded = result
      }
    } else {
      ContentUnavailableView("PDFが見つかりません", icon: .docQuestionmark)
    }
  }
}

/// Constructed off the main actor, then handed over exclusively to PDFView.
private final class LoadedProjectPDF: @unchecked Sendable {
  let document: PDFDocument?
  init(url: URL) { document = PDFDocument(url: url) }
}

private struct NativeProjectPDF: UIViewRepresentable {
  var document: PDFDocument
  var pageIndex: Int

  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.autoScales = true
    view.backgroundColor = .systemBackground
    return view
  }

  func updateUIView(_ view: PDFView, context: Context) {
    guard view.document !== document else { return }
    view.document = document
    if let page = document.page(at: pageIndex) { view.go(to: page) }
  }
}
