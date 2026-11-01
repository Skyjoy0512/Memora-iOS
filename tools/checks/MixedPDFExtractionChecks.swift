import AppKit
import Foundation
import PDFKit

enum MixedPDFExtractionChecks {
  static func run(root: URL) async throws {
    let file = root.appendingPathComponent("mixed-24-pages.pdf")
    try makeDocument(file)
    let store = PDFCheckpointStore(directory: root.appendingPathComponent("mixed-checkpoints"))
    let document = PDFDocument(url: file)!
    precondition(document.page(at: 23)!.string!.contains("Document record 731"))
    precondition(!document.page(at: 23)!.string!.contains("AMBER ORBIT"))
    let result = try PDFSourceExtraction.read(file, checkpointStore: store)
    precondition(result.pageCount == 24 && result.ocrPages == [24])
    precondition(result.coverage == .partial && result.omittedPages.isEmpty && result.unreadablePages.isEmpty)
    let lastPage = result.blocks.filter { $0.page == 24 }.map(\.text).joined(separator: "\n")
    precondition(lastPage.contains("Document record 731"))
    precondition(lastPage.contains("AMBER ORBIT 6935"), "Mixed-page raster text was omitted")
    precondition(lastPage.components(separatedBy: "Document record 731").count == 2, "Digital header duplicated")
    precondition(result.notice?.contains("OCR") == true)
    let reference = try await ProjectSourceFiles.shared.write(JSONEncoder().encode(result.blocks), extension: "json")
    let source = ProjectSource(kind: .pdf, title: "Mixed source", extractedTextReference: reference,
      processingStatus: .ready, textCoverage: result.coverage)
    let index = ProjectSearchIndex(fileURL: root.appendingPathComponent("mixed-index.sqlite"))
    let context = try await SourceContentSearch.context(source: source, question: "AMBER ORBIT 6935", budget: 3_000, index: index)
    precondition(context.used.contains { $0.page == 24 && $0.excerpt.contains("AMBER ORBIT 6935") })
    var reread: [Int] = []
    let restarted = PDFCheckpointStore(directory: root.appendingPathComponent("mixed-checkpoints"))
    let restored = try PDFSourceExtraction.read(file, checkpointStore: restarted, didReadPage: { reread.append($0) })
    precondition(reread.isEmpty && restored.blocks == result.blocks && restored.ocrPages == [24])

    let failureStore = PDFCheckpointStore(directory: root.appendingPathComponent("mixed-failed-ocr"))
    let failed = try PDFSourceExtraction.read(file, checkpointStore: failureStore, recognizeText: { _ in
      throw NSError(domain: "InjectedVisionFailure", code: 1)
    })
    precondition(failed.ocrFailedPages == [24] && failed.coverage == .partial)
    precondition(failed.blocks.contains { $0.page == 24 && $0.text.contains("Document record 731") })
    precondition(!failed.blocks.contains { $0.text.contains("AMBER ORBIT") })
    precondition(failed.notice?.contains("24") == true && failed.notice?.contains("再") == true)
    var retried: [Int] = []
    let recovered = try PDFSourceExtraction.read(file, checkpointStore: failureStore, didReadPage: { retried.append($0) })
    precondition(retried == [24] && recovered.ocrFailedPages.isEmpty)
    precondition(recovered.blocks.contains { $0.page == 24 && $0.text.contains("AMBER ORBIT 6935") })

    // The nested Form is a real PDF object graph, not a detector fixture. An
    // unreferenced self-cycle tests bounded inspection without rendering it.
    let cycle = root.appendingPathComponent("cyclic-image-resources.pdf")
    try makeDocument(cycle, pageCount: 1, cyclicResources: true)
    let cyclic = try PDFSourceExtraction.read(cycle, checkpointStore: store)
    precondition(cyclic.blocks.contains { $0.text.contains("Document record 731") })
    precondition(cyclic.ocrPages == [1] && cyclic.coverage == .partial)
    print("MixedPDFExtractionChecks: PASS. Actual nested-Form raster text plus digital text on page24, no OCR on23 digital-only pages, header deduplication, page24 SQLite FTS citation, checkpoint reuse and bounded cyclic resources. Host macOS PDFKit/Vision; no iOS/device/LLM claim.")
  }

  private static func makeDocument(_ url: URL, pageCount: Int = 24, cyclicResources: Bool = false) throws {
    let image = NSImage(size: NSSize(width: 1_000, height: 400), flipped: false) { rect in
      NSColor.white.setFill(); rect.fill()
      ("AMBER ORBIT 6935" as NSString).draw(at: CGPoint(x: 60, y: 200),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 64), .foregroundColor: NSColor.black])
      return true
    }
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])!
    // Shared objects 1...6 are catalog/pages/font/image and two nested Forms.
    let kids = (0..<pageCount).map { "\(7 + $0 * 2) 0 R" }.joined(separator: " ")
    var objects: [Data] = [
      data("<< /Type /Catalog /Pages 2 0 R >>"),
      data("<< /Type /Pages /Count \(pageCount) /Kids [\(kids)] >>"),
      data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"),
      stream(jpeg, dictionary: "/Type /XObject /Subtype /Image /Width \(bitmap.pixelsWide) /Height \(bitmap.pixelsHigh) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode"),
      stream(data("q 500 0 0 200 40 350 cm /Inner Do Q"), dictionary:
        "/Type /XObject /Subtype /Form /BBox [0 0 600 800] /Resources << /XObject << /Inner 6 0 R >> >>"),
      stream(data("/Image Do"), dictionary:
        "/Type /XObject /Subtype /Form /BBox [0 0 1 1] /Resources << /XObject << /Image 4 0 R >> >>")
    ]
    if cyclicResources {
      objects[4] = stream(Data(), dictionary:
        "/Type /XObject /Subtype /Form /BBox [0 0 600 800] /Resources << /XObject << /Self 5 0 R >> >>")
    }
    for page in 0..<pageCount {
      let mixed = page == pageCount - 1
      let resources = mixed ? "/XObject << /Outer 5 0 R >>" : ""
      objects.append(data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 3 0 R >> \(resources) >> /Contents \(8 + page * 2) 0 R >>"))
      let text = "BT /F1 24 Tf 40 710 Td (Document record 731) Tj ET"
      objects.append(stream(data(text + (mixed && !cyclicResources ? "\n/Outer Do" : ""))))
    }
    var pdf = data("%PDF-1.4\n")
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
      offsets.append(pdf.count)
      pdf.append(data("\(index + 1) 0 obj\n")); pdf.append(object); pdf.append(data("\nendobj\n"))
    }
    let xref = pdf.count
    pdf.append(data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"))
    for offset in offsets { pdf.append(data(String(format: "%010d 00000 n \n", offset))) }
    pdf.append(data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"))
    try pdf.write(to: url)
  }

  private static func stream(_ content: Data, dictionary: String = "") -> Data {
    var result = data("<< \(dictionary) /Length \(content.count) >>\nstream\n")
    result.append(content); result.append(data("\nendstream"))
    return result
  }

  private static func data(_ value: String) -> Data { Data(value.utf8) }
}
