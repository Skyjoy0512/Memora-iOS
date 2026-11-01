import Foundation
import PDFKit
import Vision
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum PDFSourceExtraction {
  static func read(_ url: URL) throws -> ProjectSourceExtractionResult {
    guard url.isFileURL else { throw ProjectSourceFiles.Failure.invalidFile }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ProjectSourceFiles.Failure.invalidFile }
    guard let size = values.fileSize, size <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    guard let document = PDFDocument(url: url) else { throw ProjectSourceFiles.Failure.invalidFile }
    guard !document.isLocked else { return ProjectSourceExtractionResult(blocks: [], notice: "パスワードで保護されたPDFは解析できません。") }
    var result = ProjectSourceExtractionResult(blocks: [], pageCount: document.pageCount)
    // Page rasterizations are released after each page. Bound total output,
    // never silently label the first pages as a complete document.
    let maximumPages = 2_000
    var bytes = 0
    let started = Date.now
    for index in 0..<document.pageCount {
      try Task.checkCancellation()
      if index >= maximumPages || bytes >= 8 * 1024 * 1024 || Date.now.timeIntervalSince(started) > 180 {
        result.omittedPages = Array((index + 1)...document.pageCount)
        break
      }
      let blocks: [ProjectSourceText] = try autoreleasepool {
        guard let page = document.page(at: index) else { return [] }
        var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
          result.ocrPages.append(index + 1)
          let thumbnail = page.thumbnail(of: CGSize(width: 1_600, height: 1_600), for: .mediaBox)
          #if canImport(UIKit)
          let image = thumbnail.cgImage
          #else
          let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
          #endif
          if let image {
            do { text = try recognize(image) }
            catch is CancellationError { throw CancellationError() }
            catch { return [] }
          }
        }
        return SourceTextChunks.split(text, page: index + 1)
      }
      if blocks.isEmpty { result.unreadablePages.append(index + 1) }
      // JSON escaping is included in the storage budget.
      let added = try JSONEncoder().encode(blocks).count
      if bytes + added > 8 * 1024 * 1024 {
        result.omittedPages = Array((index + 1)...document.pageCount)
        break
      }
      bytes += added
      result.blocks += blocks
    }
    var notices: [String] = []
    if !result.unreadablePages.isEmpty {
      notices.append("文字を読み取れなかったページ: " + pageList(result.unreadablePages) + "。")
    }
    if !result.omittedPages.isEmpty {
      notices.append("解析上限により未解析のページ: " + pageList(result.omittedPages) + "。元のPDFは保存されています。")
    }
    if !result.ocrPages.isEmpty { notices.append("画像ページは端末内OCRです。図や表の配置・画像の意味は解析していません。") }
    result.coverage = result.unreadablePages.isEmpty && result.omittedPages.isEmpty && result.ocrPages.isEmpty ? .complete : .partial
    result.notice = notices.isEmpty ? nil : notices.joined(separator: "\n")
    return result
  }

  private static func pageList(_ pages: [Int]) -> String {
    pages.prefix(30).map(String.init).joined(separator: "、") + (pages.count > 30 ? "ほか\(pages.count - 30)ページ" : "")
  }

  private static func recognize(_ image: CGImage) throws -> String {
    try Task.checkCancellation()
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["ja-JP", "en-US"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
  }
}
