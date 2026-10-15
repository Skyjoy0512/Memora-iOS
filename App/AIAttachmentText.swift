import Foundation

enum AIAttachmentText {
  private static let maximumCharacters = 8_000

  static func prepare(_ attachment: AIAttachment) async -> PreparedAIAttachment {
    let job = Task.detached(priority: .userInitiated) { readContent(attachment) }
    return await withTaskCancellationHandler {
      await job.value
    } onCancel: {
      job.cancel()
    }
  }

  static func readContent(_ attachment: AIAttachment) -> PreparedAIAttachment {
    var content = PreparedAIAttachment(id: attachment.id, name: attachment.name, url: attachment.url)
    let suffix = attachment.url.pathExtension.lowercased()
    guard !["m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "ogg", "mp4", "mov", "m4v"].contains(suffix) else {
      content.failure = "音声・動画は直接解析に対応していません。「音声を取り込む」で文字起こししてください。"
      return content
    }
    do {
      let result = try ProjectSourceExtraction.read(attachment.url, includesThumbnail: false)
      try Task.checkCancellation()
      let text = result.blocks.map { block in
        block.page.map { "ページ\($0):\n\(block.text)" } ?? block.text
      }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        content.failure = result.notice ?? "参照できる文字がありません。"
        return content
      }
      content.text = String(text.prefix(maximumCharacters))
      var notices = [result.notice].compactMap { $0 }.filter { !$0.isEmpty }
      if text.count > maximumCharacters { notices.append("添付は長いため、先頭8,000文字までを読み込みました。") }
      content.notice = notices.isEmpty ? nil : notices.joined(separator: " ")
    } catch is CancellationError {
      content.failure = "添付の読み込みを停止しました。"
    } catch ProjectSourceFiles.Failure.tooLarge {
      content.failure = "ファイルは50MB以下にしてください。"
    } catch let failure as OfficeArchiveReader.Failure {
      content.failure = failure.errorDescription
    } catch {
      content.failure = "ファイルを読み込めませんでした。形式とアクセス権を確認してください。"
    }
    return content
  }

}
