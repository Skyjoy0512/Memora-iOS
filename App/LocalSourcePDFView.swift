import PDFKit
import SwiftUI

struct LocalSourcePDFView: View {
  var url: URL
  var page: Int = 1
  @State private var loaded: LoadedLocalPDF?
  @State private var scopedURL: URL?

  var body: some View {
    Group {
      if let loaded {
        if let document = loaded.document, !document.isLocked,
           let index = ProjectCitationLocation.pageIndex(page, count: document.pageCount) {
          NativeLocalPDF(document: document, pageIndex: index)
        } else {
          ContentUnavailableView("PDFを開けません", icon: .docQuestionmark,
            description: Text("ファイルの状態とページ番号を確認してください。暗号化されたPDFは対応していません。"))
        }
      } else {
        ProgressView("PDFを読み込んでいます…")
      }
    }
    .task(id: url) {
      loaded = nil
      releaseAccess()
      if url.startAccessingSecurityScopedResource() { scopedURL = url }
      let result = await Task.detached(priority: .userInitiated) { LoadedLocalPDF(url: url) }.value
      guard !Task.isCancelled else { return }
      loaded = result
    }
    .onDisappear { releaseAccess() }
  }

  private func releaseAccess() {
    scopedURL?.stopAccessingSecurityScopedResource()
    scopedURL = nil
  }
}

/// PDFKit constructs the document off the main actor before exclusive display.
private final class LoadedLocalPDF: @unchecked Sendable {
  var document: PDFDocument?
  init(url: URL) { document = PDFDocument(url: url) }
}

private struct NativeLocalPDF: UIViewRepresentable {
  var document: PDFDocument
  var pageIndex: Int

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> PDFView {
    let view = PDFView()
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.autoScales = true
    view.backgroundColor = .systemBackground
    return view
  }

  func updateUIView(_ view: PDFView, context: Context) {
    let documentChanged = view.document !== document
    guard documentChanged || context.coordinator.pageIndex != pageIndex else { return }
    if documentChanged { view.document = document }
    context.coordinator.pageIndex = pageIndex
    if let page = document.page(at: pageIndex) { view.go(to: page) }
  }

  final class Coordinator {
    var pageIndex: Int?
  }
}
