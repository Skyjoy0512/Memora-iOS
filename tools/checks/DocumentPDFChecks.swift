import Foundation
import CoreGraphics
import CoreText
import PDFKit
import ImageIO

@main struct DocumentPDFChecks {
  static func main() async throws {
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var paragraphs: [String] = []
    for index in 1...38 {
      paragraphs.append("段落P\(index) **確認した事実**と未確認の提案を区別します。担当者と期限は記録された内容だけを使います。数値は123.45、条件は変更しません。終端Q\(index)。")
    }
    let tableRows = (1...72).map { "| R-\($0) | 確認内容です。文章が折り返されてもセルの途中を切りません。 | E-\($0) |" }
    let longParagraph = (1...100).map { "長文L\($0)・👩🏽‍💻・か\u{3099}・未定を維持。" }.joined()
    let longCell = (1...110).map { "長いセルC\($0)・次のページでも全文を残します。" }.joined()
    let markdown = "## 段落と見出し\n\n" + paragraphs.joined(separator: "\n\n")
      + "\n\n## 行を保つ表\n\n| 項目 | 確認内容 | 期限 |\n| --- | --- | --- |\n" + tableRows.joined(separator: "\n")
      + "\n\n## 長い段落\n\n" + longParagraph
      + "\n\n## 1ページを超えるセル\n\n| 識別 | 内容 |\n| --- | --- |\n| LONG-ROW | " + longCell + " |"
      + "\n\n## 幅の広い表\n\n| A | B | C | D | E |\n| --- | --- | --- | --- | --- |\n| 横1 | 横2 | 横3 | 横4 | WideEnd |"
      + "\n\n```text\n日本語のコードと    空白\nhttps://example.test/" + String(repeating: "long-segment-", count: 30) + "\n```\n\n> 引用文QUOTE-EVIDENCE。\n\n- 箇条書きBULLET-FINISH\n- [ ] 未完了CHECKLIST-FINISH\n1. 番号付きORDERED-FINISH\n\n最終END-OF-DOCUMENT。 [参照リンク](https://example.test/source) と ~~過去の案~~。"
    // Stress pagination with ragged cells, different row heights and three-line identifiers.
    for length in [1, 14, 35, 80, 400, 1_500] {
      var sample = DocumentPDFLayout.Builder()
      try sample.appendTitle("境界検証", date: "2026年10月30日")
      try sample.append(.paragraph(String(repeating: "本文。", count: length)))
      try sample.append(.table(header: ["項目", "本文", "条件"], rows: [
        [String(repeating: "識別", count: 18), String(repeating: "長いセル。", count: length), "条件は未定"],
        ["次の行", "短い本文"], ["最後", "値", "条件", "追加の列"]]))
      for page in sample.pages {
        for item in page.text { precondition(item.top + item.line.height <= DocumentPDFLayout.bodyBottom + 0.01) }
        for border in page.borders { precondition(border.maxY <= DocumentPDFLayout.bodyBottom + 0.01) }
      }
    }
    let input = DocumentPDFRenderer.Input(title: "長文PDFの検証（すべて架空データ）", date: "2026年10月30日", markdown: markdown)
    let output = directory.appendingPathComponent("long-document.pdf")
    var builder = DocumentPDFLayout.Builder()
    try builder.appendTitle(input.title, date: input.date)
    try builder.append(MarkdownBlockParser.blocks(for: markdown))
    let pages = builder.pages
    precondition(pages.count > 8 && pages.count < 100)
    for (index, page) in pages.enumerated() {
      precondition(!page.text.isEmpty, "blank page \(index)")
      if index < pages.count - 1 {
        let used = (page.text.map { $0.top + $0.line.height }.max() ?? 0) - DocumentPDFLayout.margin
        precondition(used > DocumentPDFLayout.bodyHeight / 3, "unnecessary near-empty continuation page")
      }
      for text in page.text {
        precondition(text.top >= DocumentPDFLayout.margin && text.top + text.line.height <= DocumentPDFLayout.bodyBottom + 0.01)
        let bounds = CTLineGetBoundsWithOptions(text.line.glyphs, .useGlyphPathBounds)
        precondition(bounds.width <= text.width + 2, "text exceeded its column: \(text.line.text)")
      }
      for rect in page.borders + page.fills {
        precondition(rect.minY >= DocumentPDFLayout.margin && rect.maxY <= DocumentPDFLayout.bodyBottom + 0.01)
      }
    }
    func pageContaining(_ marker: String) -> Int {
      pages.firstIndex { $0.text.contains { $0.line.text.contains(marker) } } ?? -1
    }
    for index in 1...72 {
      func exactPage(_ marker: String) -> Int {
        pages.firstIndex { $0.text.contains { $0.line.text.trimmingCharacters(in: .whitespacesAndNewlines) == marker } } ?? -1
      }
      let first = exactPage("R-\(index)")
      precondition(first >= 0 && first == exactPage("E-\(index)"), "ordinary table row was divided")
    }
    for filler in 0..<25 {
      var sample = DocumentPDFLayout.Builder()
      try sample.appendTitle("見出しの境界", date: "2026年10月30日")
      for _ in 0..<filler { try sample.append(.paragraph("余白の調整。")) }
      try sample.append([
        .heading(level: 2, text: "見出しと最初の行"),
        .table(header: ["項目", "内容", "期限"], rows: [["ROW-ID", String(repeating: "確認内容です。", count: 8), "未定"]])])
      let headingPage = sample.pages.firstIndex { $0.text.contains { $0.line.text.contains("見出しと最初") } }
      let rowPage = sample.pages.firstIndex { $0.text.contains { $0.line.text.contains("ROW-ID") } }
      precondition(headingPage == rowPage, "orphaned heading before a table")
    }
    let longLines = try DocumentPDFLayout.lines(longParagraph, width: DocumentPDFLayout.bodyWidth, size: 13)
    precondition(longLines.map(\.text).joined() == longParagraph, "Unicode text was lost or duplicated")
    for line in longLines {
      precondition(!line.text.hasSuffix("\u{200D}") && !line.text.hasPrefix("\u{200D}"), "emoji sequence split")
    }
    let start = ContinuousClock.now
    _ = try DocumentPDFRenderer.write(input, to: output)
    let elapsed = start.duration(to: .now)
    guard let pdf = PDFDocument(url: output) else { preconditionFailure("unreadable PDF") }
    precondition(pdf.pageCount == pages.count)
    let extracted = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    for marker in ["確認した事実", "未確認の提案", "123.45", "WideEnd", "END-OF-DOCUMENT", "L100", "C110", "QUOTE-EVIDENCE", "CHECKLIST-FINISH", "ORDERED-FINISH"] {
      precondition(extracted.contains(marker), "missing searchable text: \(marker)")
    }
    for index in 1...72 {
      for prefix in ["R", "E"] {
        precondition(extracted.range(of: "\\b\(prefix)-\(index)\\b", options: .regularExpression) != nil, "table row missing from PDF")
      }
    }
    for index in 0..<pdf.pageCount {
      let page = pdf.page(at: index)!
      precondition(page.bounds(for: .mediaBox).size == DocumentPDFLayout.pageSize)
      precondition(page.string?.contains("\(index + 1) / \(pdf.pageCount)") == true, "missing footer")
    }
    precondition((0..<pdf.pageCount).flatMap { pdf.page(at: $0)!.annotations }.contains { $0.url?.absoluteString == "https://example.test/source" }, "link target was lost")
    let tablePages = pages.enumerated().filter { $0.element.fills.count > 0 }.map(\.offset)
    precondition(tablePages.count > 2)
    for index in tablePages {
      let text = pages[index].text.map(\.line.text).joined()
      precondition(text.contains("確認内容") || text.contains("内容"), "continuation table lacks heading")
    }
    for (name, index) in [("first-page", 0), ("table-page", tablePages.first ?? 0),
                          ("long-cell-page", pageContaining("LONG-ROW")), ("last-page", pdf.pageCount - 1)] {
      try render(pdf.page(at: index)!, to: directory.appendingPathComponent(name + ".png"))
    }
    let existing = directory.appendingPathComponent("existing.pdf")
    let originalBytes = Data("must preserve existing bytes".utf8)
    try originalBytes.write(to: existing)
    do { _ = try DocumentPDFRenderer.write(input, to: existing); preconditionFailure("overwrote existing file") } catch {}
    let preserved = try Data(contentsOf: existing)
    precondition(preserved == originalBytes)
    try FileManager.default.removeItem(at: existing)
    try contactSheet(pdf, to: directory.appendingPathComponent("all-pages.png"))
    try await cancelledOutputIsRemoved(input, directory: directory)
    do {
      _ = try DocumentPDFRenderer.write(input, to: directory.appendingPathComponent("missing-parent/failure.pdf"))
      preconditionFailure("write failure reported success")
    } catch {}
    precondition(!FileManager.default.fileExists(atPath: output.appendingPathExtension("partial").path))
    print("DocumentPDFChecks passed: \(pdf.pageCount) A4 pages in \(elapsed), vector/searchable Japanese, Unicode/emoji preserved, paragraphs and table rows, repeated headers, long cells, wide tables, complete final text, footer, cancellation and file failure cleanup")
  }

  static func cancelledOutputIsRemoved(_ input: DocumentPDFRenderer.Input, directory: URL) async throws {
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    let output = directory.appendingPathComponent("cancelled.pdf")
    let worker = Task.detached {
      try DocumentPDFRenderer.write(input, to: output) { progress in
        if case .writing(completed: 1, total: _) = progress { started.signal(); release.wait() }
      }
    }
    await Task.detached { blockUntilSignalled(started) }.value
    worker.cancel()
    release.signal()
    do { _ = try await worker.value; preconditionFailure("cancel returned a PDF") }
    catch is CancellationError {}
    precondition(!FileManager.default.fileExists(atPath: output.path))
    precondition(!FileManager.default.fileExists(atPath: output.appendingPathExtension("partial").path))
  }

  static func contactSheet(_ pdf: PDFDocument, to url: URL) throws {
    let columns = 4, cellWidth: CGFloat = 240, cellHeight: CGFloat = 350
    let rows = (pdf.pageCount + columns - 1) / columns
    let size = CGSize(width: CGFloat(columns) * cellWidth, height: CGFloat(rows) * cellHeight)
    let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.9, alpha: 1)); context.fill(CGRect(origin: .zero, size: size))
    for index in 0..<pdf.pageCount {
      let x = CGFloat(index % columns) * cellWidth + 6
      let y = size.height - CGFloat(index / columns + 1) * cellHeight + 10
      context.saveGState()
      context.translateBy(x: x, y: y)
      let scale = (cellWidth - 12) / DocumentPDFLayout.pageSize.width
      context.scaleBy(x: scale, y: scale)
      pdf.page(at: index)!.draw(with: .mediaBox, to: context)
      context.restoreGState()
    }
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
  }

  static func blockUntilSignalled(_ semaphore: DispatchSemaphore) { semaphore.wait() }

  static func render(_ page: PDFPage, to url: URL) throws {
    let size = DocumentPDFLayout.pageSize
    let scale: CGFloat = 1.5
    let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(origin: .zero, size: size))
    page.draw(with: .mediaBox, to: context)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
  }
}
