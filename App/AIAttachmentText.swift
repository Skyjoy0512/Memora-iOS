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

  /// The most bytes read from a text file. Reading a whole file and shortening
  /// the text afterwards still pulls all of it into memory; the read itself is
  /// capped instead. Much larger than the character limit, since one character
  /// can take several bytes.
  private static let maximumBytes = 512 * 1024

  /// A PDF is parsed as a whole, so it is refused before being opened when it is
  /// too large to be worth reading.
  private static let maximumPDFBytes = 50 * 1024 * 1024

  static func read(_ attachment: AIAttachment) -> Outcome {
    switch attachment.url.pathExtension.lowercased() {
    case "txt", "text", "md", "markdown", "csv", "json", "log", "srt", "vtt":
      guard let data = readPrefix(of: attachment.url, limit: maximumBytes) else {
        return .unsupported("ファイルを読み込めませんでした。")
      }
      guard let text = decodeUTF8(data) else {
        return .unsupported("UTF-8のテキストとして読めない形式です。")
      }
      return readable(text)

    case "pdf":
      if let size = try? attachment.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
         size > maximumPDFBytes {
        return .unsupported("PDFが大きすぎるため読み込めません。")
      }
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

  /// Reads at most `limit` bytes from the start of a file, so a very large file
  /// is never loaded in full just to be shortened afterwards.
  private static func readPrefix(of url: URL, limit: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    return try? handle.read(upToCount: limit)
  }

  /// Decodes UTF-8, allowing for a multibyte character cut by the read limit.
  static func decodeUTF8(_ data: Data) -> String? {
    if let text = String(data: data, encoding: .utf8) { return text }
    for dropped in 1...3 where data.count > dropped {
      if let text = String(data: data.dropLast(dropped), encoding: .utf8) { return text }
    }
    return nil
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
