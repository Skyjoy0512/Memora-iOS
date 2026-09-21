import Foundation
import PDFKit

/// Reads what the AI engines can actually use from an attachment. Only UTF-8
/// text and PDFs with a text layer can be read; images and audio cannot be
/// analysed, and the app says so rather than pretending they were sent.
enum AIAttachmentText {
  enum Outcome {
    case text(String)
    case unsupported(String)
  }

  /// The most characters sent to an engine, so one long file cannot crowd out
  /// everything else.
  private static let maximumCharacters = 8_000

  static func read(_ attachment: AIAttachment) -> Outcome {
    switch attachment.url.pathExtension.lowercased() {
    case "txt", "text", "md", "markdown", "csv", "json", "log", "srt", "vtt":
      guard let data = try? Data(contentsOf: attachment.url) else {
        return .unsupported("ファイルを読み込めませんでした。")
      }
      guard let text = String(data: data, encoding: .utf8) else {
        return .unsupported("UTF-8のテキストとして読めない形式です。")
      }
      return readable(text)

    case "pdf":
      guard let document = PDFDocument(url: attachment.url) else {
        return .unsupported("PDFを読み込めませんでした。")
      }
      let text = document.string ?? ""
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .unsupported("このPDFには文字が入っていないため（画像としてのPDF）、AI解析に対応していません。")
      }
      return readable(text)

    case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff":
      return .unsupported("画像はAI解析に対応していません。ノートの写真として取り込むと端末内に保存できます。")

    case "m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "ogg", "mp4", "mov", "m4v":
      return .unsupported("音声・動画はAI解析に対応していません。「音声を取り込む」で文字起こししてください。")

    default:
      return .unsupported("この形式はAI解析に対応していません。")
    }
  }

  private static func readable(_ text: String) -> Outcome {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .unsupported("中身が空でした。")
    }
    guard trimmed.count > maximumCharacters else {
      return .text(trimmed)
    }
    return .text(String(trimmed.prefix(maximumCharacters)) + "\n（長いため先頭のみ送信しました）")
  }
}
