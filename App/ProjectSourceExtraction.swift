import Foundation
import PDFKit
import Vision
import ImageIO
import UIKit

enum ProjectSourceExtraction {
  struct Result: Sendable {
    var blocks: [ProjectSourceText]
    var thumbnail: Data?
    var notice: String?
  }

  static func read(_ url: URL) throws -> Result {
    switch url.pathExtension.lowercased() {
    case "txt", "md", "markdown", "csv", "json", "log", "srt", "vtt":
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 512 * 1024) ?? Data()
      guard let text = AIAttachmentText.decodeUTF8(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return Result(blocks: [], notice: "UTF-8の本文を読み取れませんでした。元ファイルは保存されています。")
      }
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return Result(blocks: [ProjectSourceText(text: text)], notice: size > data.count ? "本文は先頭512KBを解析しました。" : nil)
    case "pdf":
      guard let document = PDFDocument(url: url) else { throw ProjectSourceFiles.Failure.invalidFile }
      var blocks: [ProjectSourceText] = []
      var scanned = 0
      var notices: [String] = []
      for index in 0..<min(20, document.pageCount) {
        try Task.checkCancellation()
        guard let page = document.page(at: index) else { continue }
        var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty, scanned < 3 {
          scanned += 1
          if let image = page.thumbnail(of: CGSize(width: 1_200, height: 1_200), for: .mediaBox).cgImage {
            text = try recognize(image)
          }
        } else if text.isEmpty { notices.append("画像PDFのOCRは最大3ページです。") }
        if !text.isEmpty { blocks.append(ProjectSourceText(text: String(text.prefix(12_000)), page: index + 1)) }
      }
      if document.pageCount > 20 { notices.append("先頭20ページを解析しました。") }
      notices.append("1ページあたり最大12,000文字を解析します。")
      return Result(blocks: blocks, notice: Array(Set(notices)).sorted().joined(separator: " "))
    case "png", "jpg", "jpeg", "heic", "heif", "tiff", "gif", "webp":
      guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceThumbnailMaxPixelSize: 2_000,
              kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary) else { throw ProjectSourceFiles.Failure.invalidFile }
      let text = try recognize(image)
      let thumb = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 160,
        kCGImageSourceCreateThumbnailWithTransform: true
      ] as CFDictionary).flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.75) }
      return Result(blocks: text.isEmpty ? [] : [ProjectSourceText(text: String(text.prefix(12_000)))],
        thumbnail: thumb, notice: "画像は先頭フレームのOCRで読み取った文字を参照します。画像内容のAI解析は行っていません。")
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
