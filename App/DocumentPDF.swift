import SwiftUI
import UIKit

@MainActor
enum DocumentPDF {
  static func write(_ document: MemoraDocument,
                    onProgress: @escaping @MainActor @Sendable (DocumentPDFProgress) -> Void = { _ in }) async throws -> URL {
    try Task.checkCancellation()
    guard document.companyTemplateID == nil else { throw DocumentPDFError.companyTemplateUnsupported }
    onProgress(.preparing)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(document.exportFileName)-\(UUID().uuidString).pdf")
    if document.kind == .document {
      let input = DocumentPDFRenderer.Input(title: document.displayTitle,
        date: document.createdAt.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "ja_JP"))),
        markdown: document.markdown)
      let worker = Task.detached(priority: .userInitiated) {
        try DocumentPDFRenderer.write(input, to: url) { value in Task { @MainActor in onProgress(value) } }
      }
      let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      do {
        try Task.checkCancellation()
        return result
      } catch {
        ArtifactExportFile.removeTemporary([result])
        throw error
      }
    }
    // SwiftUI drawing stays on its actor, but yields between pages so cancel and navigation remain responsive.
    let preparation = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      try PresentationExportCheck.validate(document)
      let pages = SlidePageLayout.pages(for: document)
      try Task.checkCancellation()
      return pages
    }
    let pages = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
    guard !pages.isEmpty else { throw DocumentPDFError.layoutFailed }
    var output = try DocumentPDFFile(url: url)
    var committed = false
    defer { if !committed { output.discard() } }
    try await writeSlides(pages, to: output.stagingURL, onProgress: onProgress)
    try output.commit(expectedPages: pages.count)
    committed = true
    return output.url
  }

  private static func writeSlides(_ pages: [SlidePage], to url: URL,
                                  onProgress: (DocumentPDFProgress) -> Void) async throws {
    var box = CGRect(x: 0, y: 0, width: 960, height: 540)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw DocumentPDFError.writeFailed }
    defer { pdf.closePDF() }
    onProgress(.writing(completed: 0, total: pages.count))
    for (index, page) in pages.enumerated() {
      await Task.yield()
      try Task.checkCancellation()
      let renderer = ImageRenderer(content: SlideView(page: page).frame(width: 960, height: 540))
      renderer.proposedSize = ProposedViewSize(width: 960, height: 540)
      var rendered = false
      renderer.render { _, draw in
        pdf.beginPDFPage(nil)
        draw(pdf)
        pdf.endPDFPage()
        rendered = true
      }
      guard rendered else { throw DocumentPDFError.layoutFailed }
      onProgress(.writing(completed: index + 1, total: pages.count))
    }
    try Task.checkCancellation()
  }
}
