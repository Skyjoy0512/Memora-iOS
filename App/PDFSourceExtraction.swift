import Foundation
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum PDFSourceExtraction {
  private static let lock = NSLock()

  static func read(_ url: URL, checkpointStore: PDFCheckpointStore = .shared,
                   now: () -> Date = Date.init, didReadPage: ((Int) -> Void)? = nil,
                   recognizeText: ((CGImage) throws -> [String])? = nil) throws -> ProjectSourceExtractionResult {
    lock.lock()
    defer { lock.unlock() }
    try Task.checkCancellation()
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let snapshot = try PDFSourceSnapshot(url)
    defer { snapshot.remove() }
    guard let document = PDFDocument(url: snapshot.url) else { throw ProjectSourceFiles.Failure.invalidFile }
    guard !document.isLocked else { return ProjectSourceExtractionResult(blocks: [], notice: "パスワードで保護されたPDFは解析できません。") }
    let session = checkpointStore.begin(fingerprint: snapshot.fingerprint)
    defer { checkpointStore.finish(session) }
    let completed = checkpointStore.load(fingerprint: snapshot.fingerprint, pageCount: document.pageCount, session: session)
    var result = ProjectSourceExtractionResult(blocks: [], pageCount: document.pageCount)
    let maximumBytes = 8 * 1024 * 1024
    var bytes = 0
    for page in completed {
      bytes += page.encodedBytes
      append(page, to: &result)
    }
    // Rasterizations are released per page. A new pass resumes saved pages but
    // never expands the total text/page limits for this document.
    let started = now()
    var stoppedForTime = false
    for index in completed.count..<document.pageCount {
      try Task.checkCancellation()
      guard checkpointStore.isActive(session, fingerprint: snapshot.fingerprint) else { throw CancellationError() }
      if index >= 2_000 || bytes >= maximumBytes || now().timeIntervalSince(started) > 180 {
        stoppedForTime = index < 2_000 && bytes < maximumBytes
        result.omittedPages = Array((index + 1)...document.pageCount)
        break
      }
      let page: PDFPageCheckpoint
      do {
        page = try autoreleasepool {
          guard let page = document.page(at: index) else {
            return .init(page: index + 1, blocks: [], usedOCR: false, unreadable: true)
          }
          let digitalText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          try requireTextBudget(digitalText, page: index + 1, remaining: maximumBytes - bytes)
          var text = digitalText
          let usedOCR = digitalText.isEmpty || (page.pageRef.map { PDFPageImageInspection.containsImage(in: $0) } ?? true)
          var ocrFailed = false
          if usedOCR {
            try Task.checkCancellation()
            let thumbnail = page.thumbnail(of: CGSize(width: 1_600, height: 1_600), for: .mediaBox)
            #if canImport(UIKit)
            let image = thumbnail.cgImage
            #else
            let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #endif
            if let image {
              var lines: [String]?
              do {
                if let recognizeText { lines = try recognizeText(image) }
                else { lines = try recognize(image) }
              } catch is CancellationError { throw CancellationError() }
              catch { ocrFailed = true }
              try Task.checkCancellation()
              if let lines { text = PDFPageTextMerge.merge(digitalText: digitalText, recognizedLines: lines) }
            } else { ocrFailed = true }
          }
          try requireTextBudget(text, page: index + 1, remaining: maximumBytes - bytes)
          let blocks = SourceTextChunks.split(text, page: index + 1)
          return .init(page: index + 1, blocks: blocks, usedOCR: usedOCR,
            unreadable: blocks.isEmpty, ocrFailed: ocrFailed)
        }
      } catch PageBudgetFailure.exceeded {
        result.omittedPages = Array((index + 1)...document.pageCount)
        break
      }
      try Task.checkCancellation()
      guard checkpointStore.isActive(session, fingerprint: snapshot.fingerprint) else { throw CancellationError() }
      let added = page.encodedBytes
      if bytes + added > maximumBytes {
        result.omittedPages = Array((index + 1)...document.pageCount)
        break
      }
      bytes += added
      append(page, to: &result)
      if page.ocrFailed != true {
        checkpointStore.save(page, fingerprint: snapshot.fingerprint, pageCount: document.pageCount, session: session)
      }
      didReadPage?(index + 1)
    }
    try Task.checkCancellation()
    guard checkpointStore.isActive(session, fingerprint: snapshot.fingerprint) else { throw CancellationError() }
    try snapshot.verifyOriginal()
    if stoppedForTime, let page = result.omittedPages.first, page > 1,
       checkpointStore.load(fingerprint: snapshot.fingerprint, pageCount: document.pageCount, session: session).count == page - 1 {
      result.resumePage = page
    }
    var notices: [String] = []
    if !result.unreadablePages.isEmpty {
      notices.append("文字を読み取れなかったページ: " + pageList(result.unreadablePages) + "。")
    }
    if !result.ocrFailedPages.isEmpty {
      notices.append("画像の文字を読み取れなかったページ: " + pageList(result.ocrFailedPages) +
        "。読み取れた本文と元のPDFは保持しています。再試行できます。")
    }
    if !result.omittedPages.isEmpty {
      let reason = stoppedForTime ? "まだ読み取っていないページ: " : "解析上限により未解析のページ: "
      notices.append(reason + pageList(result.omittedPages) + "。元のPDFは保存されています。" +
        (result.resumePage != nil ? "再試行すると続きから読み取ります。" : ""))
    }
    if !result.ocrPages.isEmpty { notices.append("画像ページは端末内OCRです。図や表の配置・画像の意味は解析していません。") }
    result.coverage = result.unreadablePages.isEmpty && result.omittedPages.isEmpty && result.ocrPages.isEmpty ? .complete : .partial
    result.notice = notices.isEmpty ? nil : notices.joined(separator: "\n")
    return result
  }

  private static func append(_ page: PDFPageCheckpoint, to result: inout ProjectSourceExtractionResult) {
    result.blocks += page.blocks
    if page.usedOCR { result.ocrPages.append(page.page) }
    if page.unreadable { result.unreadablePages.append(page.page) }
    if page.ocrFailed == true { result.ocrFailedPages.append(page.page) }
  }

  private static func requireTextBudget(_ text: String, page: Int, remaining: Int) throws {
    guard text.utf8.count <= remaining else { throw PageBudgetFailure.exceeded }
    guard !text.isEmpty else { return }
    // Count the minimum serialized block before merge tokenization or chunk
    // allocation. Splitting adds block metadata, checked by the final encoder.
    var encoded = try JSONEncoder().encode([ProjectSourceText(text: "", page: page)]).count
    for byte in text.utf8 {
      let cost: Int
      switch byte {
      case 0x08, 0x09, 0x0A, 0x0C, 0x0D, 0x22, 0x5C: cost = 2
      case 0x00...0x1F: cost = 6
      default: cost = 1
      }
      guard encoded <= remaining - cost else { throw PageBudgetFailure.exceeded }
      encoded += cost
    }
  }

  private enum PageBudgetFailure: Error { case exceeded }

  private static func pageList(_ pages: [Int]) -> String {
    pages.prefix(30).map(String.init).joined(separator: "、") + (pages.count > 30 ? "ほか\(pages.count - 30)ページ" : "")
  }

  private static func recognize(_ image: CGImage) throws -> [String] {
    try Task.checkCancellation()
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["ja-JP", "en-US"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    try Task.checkCancellation()
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
  }
}
