import Foundation

enum AIAttachmentText {
  static let maximumCharacters = 60_000

  static func prepare(_ attachment: AIAttachment, question: String = "", maximumCharacters: Int = maximumCharacters, vocabulary: [String] = []) async -> PreparedAIAttachment {
    var prepared = PreparedAIAttachment(id: attachment.id, name: attachment.name, url: attachment.url,
      preparedQuestion: question, additionalFileIDs: attachment.additionalFiles?.map(\.id))
    guard attachment.files.count <= 10 else { prepared.failure = "添付は10件までです。"; return prepared }
    var parts: [String] = [], notices: [String] = []
    let budget = max(300, min(Self.maximumCharacters, maximumCharacters) / attachment.files.count - 100)
    for file in attachment.files {
      do {
        try Task.checkCancellation()
        let result = try await SourceExtractionCache.shared.extract(file.url, vocabulary: vocabulary)
        guard !result.blocks.isEmpty else {
          prepared.failure = "「\(file.name)」: " + (result.notice ?? "参照できる文字がありません。")
          return prepared
        }
        let selection = await Task.detached(priority: .utility) {
          SourceTextSelection.text(blocks: result.blocks, question: question, budget: budget)
        }.value
        guard !selection.text.isEmpty else { prepared.failure = "質問に使える本文が見つかりませんでした。"; return prepared }
        parts.append("資料「\(file.name.prefix(100))」\n" + selection.text)
        if let notice = result.notice { notices.append("「\(file.name)」: " + notice) }
        if selection.isExcerpt { notices.append("「\(file.name)」は全ページの文字から選んだ抜粋です。全文を読んだ回答とは限りません。") }
      } catch is CancellationError { prepared.failure = "添付の読み込みを停止しました。"; return prepared }
      catch { prepared.failure = "「\(file.name)」: " + error.localizedDescription; return prepared }
    }
    prepared.text = parts.joined(separator: "\n\n")
    prepared.notice = notices.isEmpty ? nil : notices.joined(separator: "\n")
    return prepared
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
      if text.count > maximumCharacters { notices.append("添付は長いため、先頭\(maximumCharacters)文字までを読み込みました。") }
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
