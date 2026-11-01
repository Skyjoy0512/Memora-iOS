import AppKit
import Foundation
import PDFKit
import CryptoKit
import SQLite3

@main struct SourceIntakeChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    PDFPageTextMergeChecks.run()
    try await MixedPDFExtractionChecks.run(root: root)
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
    var summarized = source
    summarized.summary = "生成された要約"
    summarized.summaryStatus = .ready
    summarized.summaryUpdatedAt = .now
    precondition(summarized.hasSameReadableEvidence(as: source))
    summarized.privacy.allowsCloudAI = true
    precondition(!summarized.hasSameReadableEvidence(as: source))
    summarized = source
    summarized.extractedTextReference = "replacement.json"
    precondition(!summarized.hasSameReadableEvidence(as: source))
    summarized = source
    summarized.projectID = UUID()
    precondition(!summarized.hasSameReadableEvidence(as: source))
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
    try await checkpointChecks(root: root, pdf: pdf, scan: scan)
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
    print("SourceIntakeChecks: PASS. Actual 24-page PDF extraction, page-24 SQLite FTS citation, absent evidence refusal, late-page attachment selection, five-page native Vision OCR, SQLite page continuation after cancellation/time budget, no repeated completed-page OCR, changed-original/corruption/deletion invalidation, timed SRT/VTT, lossless chunks and legacy decoding. Host macOS execution; no iOS/device/model/network claim.")
  }

  static func checkpointChecks(root: URL, pdf: URL, scan: URL) async throws {
    let directory = root.appendingPathComponent("cancel-checkpoints", isDirectory: true)
    let checkpoints = PDFCheckpointStore(directory: directory)
    let cancelled = Task.detached {
      try PDFSourceExtraction.read(pdf, checkpointStore: checkpoints, didReadPage: { page in
        if page == 2 { withUnsafeCurrentTask { $0?.cancel() } }
      })
    }
    do { _ = try await cancelled.value; preconditionFailure("Cancellation was ignored") }
    catch is CancellationError {}
    let fingerprint = digest(try Data(contentsOf: pdf))
    let session = checkpoints.begin(fingerprint: fingerprint)
    let stored = checkpoints.load(fingerprint: fingerprint, pageCount: 24, session: session)
    checkpoints.finish(session)
    precondition(stored.map(\.page) == [1, 2])
    var newlyRead: [Int] = []
    let restarted = PDFCheckpointStore(directory: directory)
    let resumed = try PDFSourceExtraction.read(pdf, checkpointStore: restarted, didReadPage: { newlyRead.append($0) })
    precondition(newlyRead == Array(3...24) && resumed.omittedPages.isEmpty && resumed.resumePage == nil)
    precondition(resumed.blocks.contains { $0.page == 24 && $0.text.contains("SAPPHIRE") })
    var repeated: [Int] = []
    _ = try PDFSourceExtraction.read(pdf, checkpointStore: restarted, didReadPage: { repeated.append($0) })
    precondition(repeated.isEmpty)

    let timedDirectory = root.appendingPathComponent("time-checkpoints", isDirectory: true)
    let timedStore = PDFCheckpointStore(directory: timedDirectory)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var count = 0
    let partial = try PDFSourceExtraction.read(scan, checkpointStore: timedStore,
      now: { start.addingTimeInterval(count >= 2 ? 181 : 0) }, didReadPage: { _ in count += 1 })
    precondition(count == 2 && partial.resumePage == 3 && partial.omittedPages == [3, 4, 5])
    precondition(partial.ocrPages == [1, 2] && partial.coverage == .partial)
    var newlyRecognized: [Int] = []
    let timedRestart = PDFCheckpointStore(directory: timedDirectory)
    let finished = try PDFSourceExtraction.read(scan, checkpointStore: timedRestart, didReadPage: { newlyRecognized.append($0) })
    precondition(newlyRecognized == [3, 4, 5] && finished.ocrPages == [1, 2, 3, 4, 5])
    precondition(finished.unreadablePages == [5] && finished.omittedPages.isEmpty && finished.resumePage == nil)

    // Missing new optional metadata must still decode older derived snapshots.
    let snapshot = SourceExtractionSnapshot(partial, thumbnailReference: nil, thumbnailFingerprint: nil)
    let encoded = try JSONEncoder().encode(snapshot)
    var legacy = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    legacy.removeValue(forKey: "resumePage")
    let decoded = try JSONDecoder().decode(SourceExtractionSnapshot.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    precondition(decoded.resumePage == nil && decoded.result(thumbnail: nil)?.blocks == partial.blocks)

    let corruptDirectory = root.appendingPathComponent("corrupt-checkpoints", isDirectory: true)
    let corruptStore = PDFCheckpointStore(directory: corruptDirectory)
    count = 0
    _ = try PDFSourceExtraction.read(pdf, checkpointStore: corruptStore,
      now: { start.addingTimeInterval(count >= 2 ? 181 : 0) }, didReadPage: { _ in count += 1 })
    try execute("UPDATE pages SET checksum = 'changed' WHERE page = 1;", directory: corruptDirectory)
    var afterCorruption: [Int] = []
    _ = try PDFSourceExtraction.read(pdf, checkpointStore: PDFCheckpointStore(directory: corruptDirectory),
      didReadPage: { afterCorruption.append($0) })
    precondition(afterCorruption == Array(1...24))

    let mutable = root.appendingPathComponent("changing.pdf")
    try FileManager.default.copyItem(at: pdf, to: mutable)
    let mutationStore = PDFCheckpointStore(directory: root.appendingPathComponent("mutation-checkpoints", isDirectory: true))
    count = 0
    _ = try PDFSourceExtraction.read(mutable, checkpointStore: mutationStore,
      now: { start.addingTimeInterval(count >= 2 ? 181 : 0) }, didReadPage: { _ in count += 1 })
    try makeTextPDF(mutable, prefix: "CHANGED ORIGINAL")
    var afterMutation: [Int] = []
    let replacement = try PDFSourceExtraction.read(mutable, checkpointStore: mutationStore, didReadPage: { afterMutation.append($0) })
    precondition(afterMutation == Array(1...24))
    precondition(replacement.blocks.contains { $0.text.contains("CHANGED ORIGINAL") })

    let deletionStore = PDFCheckpointStore(directory: root.appendingPathComponent("deleted-checkpoints", isDirectory: true))
    do {
      _ = try PDFSourceExtraction.read(pdf, checkpointStore: deletionStore, didReadPage: { page in
        if page == 2 { deletionStore.invalidate(fingerprints: [fingerprint]) }
      })
      preconditionFailure("Deleted original's extraction continued")
    } catch is CancellationError {}
    let freshSession = deletionStore.begin(fingerprint: fingerprint)
    let afterDeletion = deletionStore.load(fingerprint: fingerprint, pageCount: 24, session: freshSession)
    deletionStore.finish(freshSession)
    precondition(afterDeletion.isEmpty)
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func execute(_ sql: String, directory: URL) throws {
    var db: OpaquePointer?
    precondition(sqlite3_open(directory.appendingPathComponent("pages.sqlite").path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
  }

  static func makeTextPDF(_ url: URL, prefix: String = "Ordinary background") throws {
    var box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let consumer = CGDataConsumer(url: url as CFURL)!
    let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
    for page in 1...24 {
      context.beginPDFPage(nil)
      let graphics = NSGraphicsContext(cgContext: context, flipped: false)
      NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
      let text = page == 24 ? "SAPPHIRE QUARTZ 2468" : "\(prefix) page \(page)"
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
