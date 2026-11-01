import AppKit
import Foundation
import PDFKit

@main struct SourceIntakeChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let pdf = root.appendingPathComponent("24-pages.pdf")
    try makeTextPDF(pdf)
    let result = try PDFSourceExtraction.read(pdf)
    precondition(result.pageCount == 24 && result.omittedPages.isEmpty && result.unreadablePages.isEmpty)
    precondition(result.blocks.contains { $0.page == 24 && $0.text.contains("SAPPHIRE QUARTZ 2468") })
    precondition(result.coverage == .complete)
    let reference = try await ProjectSourceFiles.shared.write(JSONEncoder().encode(result.blocks), extension: "json")
    let source = ProjectSource(projectID: UUID(), kind: .pdf, title: "タイトルに答えがない資料", extractedTextReference: reference,
      processingStatus: .ready, textCoverage: result.coverage)
    let index = ProjectSearchIndex(fileURL: root.appendingPathComponent("index.sqlite"))
    let context = try await SourceContentSearch.context(source: source, question: "SAPPHIRE QUARTZ 2468", budget: 4_000, index: index)
    precondition(context.used.contains { $0.page == 24 && $0.excerpt.contains("SAPPHIRE QUARTZ 2468") })
    precondition(context.used.allSatisfy { $0.target == .source(source.id) })
    let unrelated = try await SourceContentSearch.context(source: source, question: "PLATINUM ZIRCON 9988", budget: 4_000, index: index)
    precondition(unrelated.used.isEmpty)
    let selected = SourceTextSelection.text(blocks: result.blocks, question: "SAPPHIRE QUARTZ 2468", budget: 700)
    precondition(selected.isExcerpt && selected.text.contains("SAPPHIRE QUARTZ 2468") && selected.text.contains("ページ24"))
    let scan = root.appendingPathComponent("five-scans.pdf")
    try makeScanPDF(scan)
    let scanned = try PDFSourceExtraction.read(scan)
    precondition(scanned.pageCount == 5 && scanned.ocrPages == [1, 2, 3, 4, 5])
    precondition(scanned.blocks.contains { $0.page == 4 && $0.text.uppercased().contains("SAPPHIRE") })
    precondition(scanned.unreadablePages == [5] && scanned.coverage == .partial)
    let captions = SubtitleText.blocks("WEBVTT\n\n00:00:02.500 --> 00:00:05.000\nFirst idea\n\n00:01:12.000 --> 00:01:18.000\nLater evidence\n")
    precondition(captions.count == 2 && captions[0].time == 2.5 && captions[1].time == 72)
    precondition(SubtitleText.timestamp("999999999999999:00:00") == nil)
    precondition(SubtitleText.blocks("時刻のない原文").allSatisfy { $0.time == nil })
    let chunks = SourceTextChunks.split(String(repeating: "後半", count: 20_000), page: 27)
    precondition(chunks.map(\.text).joined() == String(repeating: "後半", count: 20_000))
    precondition(chunks.allSatisfy { $0.page == 27 && $0.text.count <= 1_200 })
    let earlierWeakHits = (0..<10).map { _ in ProjectCitation(target: .source(UUID()), title: "QUARTZ",
      excerpt: "Background material", page: 1) }
    let strong = ProjectCitation(target: .source(UUID()), title: "Older source",
      excerpt: "SAPPHIRE QUARTZ 2468 is the exact measured result", page: 24)
    let ranked = SourceEvidenceRanking.select(earlierWeakHits + [strong], question: "SAPPHIRE QUARTZ 2468", budget: 2_000)
    precondition(ranked.contains { $0.target == strong.target })
    let lateBlocks = SourceTextChunks.split(String(repeating: "ordinary background ", count: 110_000)) +
      [ProjectSourceText(text: "UNIQUE LATE EVIDENCE 7777", page: 99)]
    let lateReference = try await ProjectSourceFiles.shared.write(JSONEncoder().encode(lateBlocks), extension: "json")
    let longSource = ProjectSource(kind: .document, title: "Long source", extractedTextReference: lateReference, processingStatus: .ready)
    let lateContext = try await SourceContentSearch.context(source: longSource, question: "UNIQUE LATE EVIDENCE 7777", budget: 2_000, index: index)
    precondition(lateContext.used.contains { $0.page == 99 })
    let legacy = ProjectSource(kind: .web, title: "legacy", originalURL: URL(string: "https://example.com"))
    let oldData = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
    let old = try JSONDecoder().decode(ProjectSource.self, from: JSONSerialization.data(withJSONObject: oldData))
    precondition(old.summary == nil && old.captionFileReference == nil && old.id == legacy.id)
    print("SourceIntakeChecks: PASS. Actual 24-page PDF extraction, page-24 SQLite FTS citation, absent evidence refusal, late-page attachment selection, five-page native Vision OCR with unreadable-page distinction, timed SRT/VTT, lossless long-text chunks and legacy source decoding. Host macOS execution; no iOS/device/model/network claim.")
  }

  static func makeTextPDF(_ url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let consumer = CGDataConsumer(url: url as CFURL)!
    let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
    for page in 1...24 {
      context.beginPDFPage(nil)
      let graphics = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
      let text = page == 24 ? "SAPPHIRE QUARTZ 2468" : "Ordinary background page \(page)"
      (text as NSString).draw(at: CGPoint(x: 40, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
      NSGraphicsContext.restoreGraphicsState()
      context.endPDFPage()
    }
    context.closePDF()
  }

  static func makeScanPDF(_ url: URL) throws {
    let document = PDFDocument()
    for page in 1...5 {
      let image = NSImage(size: NSSize(width: 1_000, height: 1_000), flipped: false) { rect in
        NSColor.white.setFill(); rect.fill()
        if page < 5 {
          ("SAPPHIRE PAGE \(page)" as NSString).draw(at: CGPoint(x: 80, y: 700),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 50), .foregroundColor: NSColor.black])
        }
        return true
      }
      document.insert(PDFPage(image: image)!, at: page - 1)
    }
    precondition(document.write(to: url))
  }
}
