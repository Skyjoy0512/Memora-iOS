import Foundation

enum AIAttachmentText {
  static let maximumCharacters = 60_000

  static func prepare(_ attachment: AIAttachment, question: String = "", maximumCharacters: Int = maximumCharacters, vocabulary: [String] = []) async -> PreparedAIAttachment {
    var prepared = PreparedAIAttachment(id: attachment.id, name: attachment.name, url: attachment.url,
      preparedQuestion: question, additionalFileIDs: attachment.additionalFiles?.map(\.id))
    guard attachment.files.count <= 10 else { prepared.failure = "添付は10件までです。"; return prepared }
    var parts: [String] = [], notices: [String] = []
    var citations: [AIAttachmentCitation] = []
    let totalBudget = max(0, min(Self.maximumCharacters, maximumCharacters))
    for (index, file) in attachment.files.enumerated() {
      do {
        try Task.checkCancellation()
        let reference = AIAttachmentFileReference(AIAttachment(id: file.id, name: file.name,
          url: file.url, originalURL: file.originalURL, sourceMetadata: file.sourceMetadata))
        let result = try await SourceExtractionCache.shared.extract(file.url, vocabulary: vocabulary)
        guard !result.blocks.isEmpty else {
          prepared.failure = "「\(file.name)」: " + (result.notice ?? "参照できる文字がありません。")
          return prepared
        }
        let header = "資料「\(file.name.prefix(100))」\n"
        let fileBudget = max(0, totalBudget / attachment.files.count - (index == 0 ? 0 : 2) - header.count)
        let slots = min(24, (64 - citations.count) / (attachment.files.count - index))
        let selection = await Task.detached(priority: .utility) {
          SourceTextSelection.selectedBlocks(blocks: result.blocks, question: question, budget: fileBudget,
            maximumBlocks: slots, maximumBlockUTF8Bytes: 8_000, additionalCharactersPerBlock: 16)
        }.value
        var excerpts: [String] = []
        for block in selection.blocks {
          // Accessible originals can be read before a durable conversation copy exists.
          guard let reference else {
            let location = block.page.map { "[ページ\($0)] " } ?? block.time.map { "[\(Int($0))秒] " } ?? ""
            excerpts.append(location + block.text)
            continue
          }
          guard let citation = AIAttachmentCitation(number: citations.count + 1, file: reference,
            excerpt: block.text, page: block.page, time: block.time) else { continue }
          excerpts.append(citation.contextText)
          citations.append(citation)
        }
        guard !excerpts.isEmpty else { prepared.failure = "質問に使える本文が見つかりませんでした。"; return prepared }
        parts.append(header + excerpts.joined(separator: "\n\n"))
        if let notice = result.notice { notices.append("「\(file.name)」: " + notice) }
        if selection.isExcerpt { notices.append("「\(file.name)」は全ページの文字から選んだ抜粋です。全文を読んだ回答とは限りません。") }
      } catch is CancellationError { prepared.failure = "添付の読み込みを停止しました。"; return prepared }
      catch { prepared.failure = "「\(file.name)」: " + error.localizedDescription; return prepared }
    }
    prepared.text = parts.joined(separator: "\n\n")
    prepared.attachmentCitations = AIAttachmentCitation.retained(citations, in: prepared.text ?? "")
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
