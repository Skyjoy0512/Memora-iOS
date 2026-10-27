import SwiftUI
import UIKit

/// Renders a document to PDF for the share sheet: slides one per 16:9 page, a
/// written document on A4 pages. The text stays vector, so it can be selected
/// and searched in the file.
@MainActor
enum DocumentPDF {
  enum ExportError: Error {
    case renderFailed
  }

  private static let a4 = CGSize(width: 595, height: 842)
  private static let pageMargin: CGFloat = 48

  static func write(_ document: MemoraDocument) throws -> URL {
    try PresentationExportCheck.validate(document)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(document.exportFileName)-\(UUID().uuidString.prefix(8)).pdf")
    switch document.kind {
    case .slides:
      try writeSlides(document, to: url)
    case .document:
      try writePages(document, to: url)
    }
    return url
  }

  private static func writeSlides(_ document: MemoraDocument, to url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 960, height: 540)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ExportError.renderFailed }
    let pages = SlidePageLayout.pages(for: document)
    for page in pages {
      let renderer = ImageRenderer(content: SlideView(page: page).frame(width: 960, height: 540))
      renderer.proposedSize = ProposedViewSize(width: 960, height: 540)
      renderer.render { _, draw in
        pdf.beginPDFPage(nil)
        draw(pdf)
        pdf.endPDFPage()
      }
    }
    pdf.closePDF()
  }

  /// Lays the document out as one tall column and cuts it into A4 pages.
  private static func writePages(_ document: MemoraDocument, to url: URL) throws {
    let content = DocumentPDFContent(document: document)
      .frame(width: a4.width - pageMargin * 2)
      .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: content)
    renderer.proposedSize = ProposedViewSize(width: a4.width - pageMargin * 2, height: nil)

    var box = CGRect(origin: .zero, size: a4)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ExportError.renderFailed }
    var didRender = false
    renderer.render { size, draw in
      guard size.height > 0 else { return }
      didRender = true
      let bodyHeight = a4.height - pageMargin * 2
      let pageCount = max(1, Int(ceil(size.height / bodyHeight)))
      for page in 0..<pageCount {
        pdf.beginPDFPage(nil)
        pdf.saveGState()
        // PDF space runs bottom-up; the column's top sits at the page's top
        // margin, shifted up by the pages already printed.
        pdf.clip(to: CGRect(x: 0, y: pageMargin, width: a4.width, height: bodyHeight))
        pdf.translateBy(
          x: pageMargin,
          y: a4.height - pageMargin - size.height + CGFloat(page) * bodyHeight
        )
        draw(pdf)
        pdf.restoreGState()
        pdf.endPDFPage()
      }
    }
    pdf.closePDF()
    guard didRender else { throw ExportError.renderFailed }
  }
}

/// A written document as printed: title, date and the markdown body.
private struct DocumentPDFContent: View {
  var document: MemoraDocument

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(document.displayTitle)
          .font(.title.bold())
        Text(document.createdAt.formatted(date: .long, time: .omitted))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      MarkdownDocumentView(markdown: document.markdown)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(.black)
  }
}
