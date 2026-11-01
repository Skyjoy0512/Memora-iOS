import Foundation
import PDFKit
import Vision
import ImageIO
import UIKit

enum ProjectSourceExtraction {
  typealias Result = ProjectSourceExtractionResult

  static func extract(_ url: URL) async throws -> Result {
    let job = Task.detached(priority: .utility) { try read(url) }
    return try await withTaskCancellationHandler {
      try await job.value
    } onCancel: {
      job.cancel()
    }
  }

  static func read(_ url: URL, includesThumbnail: Bool = true) throws -> Result {
    guard url.isFileURL else { throw ProjectSourceFiles.Failure.invalidFile }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize else { throw ProjectSourceFiles.Failure.invalidFile }
    guard size <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    try Task.checkCancellation()
    switch url.pathExtension.lowercased() {
    case "txt", "text", "md", "markdown", "csv", "json", "log", "srt", "vtt":
      guard let result = try? BoundedTextReader.read(url, maximumBytes: 4 * 1024 * 1024),
            !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        try Task.checkCancellation()
        return Result(blocks: [], notice: "UTF-8の本文を読み取れませんでした。元ファイルは保存されています。")
      }
      let blocks = ["srt", "vtt"].contains(url.pathExtension.lowercased())
        ? SubtitleText.blocks(result.text) : SourceTextChunks.split(result.text)
      return Result(blocks: blocks, notice: result.wasTruncated ? "本文は先頭4MBを解析しました。" : nil,
        coverage: result.wasTruncated ? .partial : .complete)
    case "pdf":
      return try PDFSourceExtraction.read(url)
    case "png", "jpg", "jpeg", "heic", "heif", "tiff", "gif", "webp":
      guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 2_000,
              kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { throw ProjectSourceFiles.Failure.invalidFile }
      let text = try recognize(image)
      let thumb = includesThumbnail ? CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 160,
        kCGImageSourceCreateThumbnailWithTransform: true
      ] as CFDictionary).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.75) } : nil
      return Result(blocks: text.isEmpty ? [] : [ProjectSourceText(text: String(text.prefix(12_000)))],
        thumbnail: thumb, notice: "画像は先頭フレームのOCRで読み取った文字を参照します。画像内容のAI解析は行っていません。",
        coverage: .partial)
    case "docx", "pptx", "xlsx":
      let result = try OfficeDocumentExtraction.read(url)
      return Result(blocks: result.blocks, notice: result.notice, coverage: .partial)
    default:
      return Result(blocks: [], notice: "この形式は保存・プレビューのみ対応しています。本文解析には対応していません。")
    }
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
