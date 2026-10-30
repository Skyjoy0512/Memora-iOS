import Foundation
import CoreGraphics
import CoreText

// Core Text lays out and writes on the worker, without a full-document bitmap or main-thread view tree.
enum DocumentPDFRenderer {
  struct Input: Sendable {
    var title: String
    var date: String
    var markdown: String
    // Explicit blocks preserve record sections without interpreting their text as markdown headings.
    var blocks: [MarkdownBlock]? = nil
  }

  static func write(_ input: Input, to url: URL,
                    onProgress: @Sendable (DocumentPDFProgress) -> Void = { _ in }) throws -> URL {
    var output = try DocumentPDFFile(url: url)
    var committed = false
    defer { if !committed { output.discard() } }
    try Task.checkCancellation()
    onProgress(.preparing)
    var builder = DocumentPDFLayout.Builder()
    try builder.appendTitle(input.title, date: input.date)
    try builder.append(input.blocks ?? MarkdownBlockParser.blocks(for: input.markdown))
    try Task.checkCancellation()
    try render(builder.pages, to: output.stagingURL, onProgress: onProgress)
    try output.commit(expectedPages: builder.pages.count)
    committed = true
    return output.url
  }

  private static func render(_ pages: [DocumentPDFLayout.Page], to url: URL,
                             onProgress: @Sendable (DocumentPDFProgress) -> Void) throws {
    var box = CGRect(origin: .zero, size: DocumentPDFLayout.pageSize)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw DocumentPDFError.writeFailed }
    defer { pdf.closePDF() }
    onProgress(.writing(completed: 0, total: pages.count))
    for (index, page) in pages.enumerated() {
      try Task.checkCancellation()
      pdf.beginPDFPage(nil)
      pdf.setFillColor(CGColor(gray: 1, alpha: 1))
      pdf.fill(box)
      pdf.setFillColor(CGColor(gray: 0.95, alpha: 1))
      for rect in page.fills { pdf.fill(flipped(rect)) }
      pdf.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
      pdf.setLineWidth(0.5)
      for rect in page.borders {
        if rect.height == 0 {
          pdf.move(to: CGPoint(x: rect.minX, y: box.height - rect.minY))
          pdf.addLine(to: CGPoint(x: rect.maxX, y: box.height - rect.minY))
          pdf.strokePath()
        } else { pdf.stroke(flipped(rect)) }
      }
      for placement in page.text {
        pdf.textMatrix = .identity
        pdf.textPosition = CGPoint(x: placement.x, y: box.height - placement.top - placement.line.ascent)
        CTLineDraw(placement.line.glyphs, pdf)
        drawInlineAnnotations(placement, in: pdf)
      }
      let footer = CTLineCreateWithAttributedString(DocumentPDFLayout.styled("Memora · \(index + 1) / \(pages.count)", size: 9, bold: false))
      let width = CTLineGetTypographicBounds(footer, nil, nil, nil)
      pdf.textPosition = CGPoint(x: (box.width - width) / 2, y: 23)
      CTLineDraw(footer, pdf)
      pdf.endPDFPage()
      if (index + 1).isMultiple(of: max(1, pages.count / 100)) || index + 1 == pages.count {
        onProgress(.writing(completed: index + 1, total: pages.count))
      }
    }
    try Task.checkCancellation()
  }

  private static func flipped(_ rect: CGRect) -> CGRect {
    CGRect(x: rect.minX, y: DocumentPDFLayout.pageSize.height - rect.maxY, width: rect.width, height: rect.height)
  }

  private static func drawInlineAnnotations(_ placement: DocumentPDFLayout.Text, in pdf: CGContext) {
    let line = placement.line.glyphs
    let baseline = DocumentPDFLayout.pageSize.height - placement.top - placement.line.ascent
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
      let attributes = CTRunGetAttributes(run) as NSDictionary
      let range = CTRunGetStringRange(run)
      let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
      let end = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
      let left = placement.x + min(start, end), width = abs(end - start)
      if let url = attributes["MemoraPDFURL"] as? URL {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        _ = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil)
        pdf.setURL(url as CFURL, for: CGRect(x: left, y: baseline - descent, width: width, height: ascent + descent))
      }
      if attributes["MemoraPDFStrike"] as? Bool == true {
        pdf.setStrokeColor(CGColor(gray: 0.2, alpha: 1))
        pdf.setLineWidth(0.6)
        pdf.move(to: CGPoint(x: left, y: baseline + placement.line.ascent * 0.35))
        pdf.addLine(to: CGPoint(x: left + width, y: baseline + placement.line.ascent * 0.35))
        pdf.strokePath()
      }
    }
  }
}
