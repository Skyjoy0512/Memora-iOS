import Foundation

enum AIAnswerDocumentBuilder {
  static func make(message: AIChatMessage, question: String?) -> MemoraDocument {
    let questionTitle = question?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") ?? ""
    let answerTitle = AnswerCitations.stripped(message.text)
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#*> -").union(.whitespaces)) }
      .first { !$0.isEmpty } ?? "保存した回答"
    let candidate = questionTitle.isEmpty ? answerTitle : questionTitle
    let title = String(candidate.prefix(48)) + (candidate.count > 48 ? "…" : "")
    var markdown = AnswerCitations.saved(message.text, sources: message.sources)
    let references = message.sources.enumerated().compactMap { index, source -> String? in
      guard let url = MeetingLink.url(for: source.meetingID) else { return nil }
      let name = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let label = "資料\(index + 1): \(name.isEmpty ? "無題の記録" : name)"
      return "- [\(escape(label))](\(url.absoluteString))"
    }
    if !references.isEmpty {
      markdown += "\n\n## 参照した記録\n\n" + references.joined(separator: "\n")
      markdown += "\n\nリンクは、元の記録がある端末のMemoraで開けます。"
    }
    return MemoraDocument(title: title, kind: .document, markdown: markdown)
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .reduce(into: "") { result, character in
        if "\\[]*_`".contains(character) { result.append("\\") }
        result.append(character)
      }
  }
}
