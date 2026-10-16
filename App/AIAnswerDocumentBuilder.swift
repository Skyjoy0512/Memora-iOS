import Foundation

enum AIAnswerDocumentBuilder {
  static func make(message: AIChatMessage, question: String?, provenance: ArtifactProvenance? = nil) -> MemoraDocument {
    let provenance = provenance ?? message.artifactProvenance
    let allowed = AnswerSourceCitation.targets(provenance: provenance, meetingIDs: message.sources.map(\.meetingID))
    let answer = NativeAIInterface.response(message.text).markdown
    let questionTitle = question?.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") ?? ""
    let answerTitle = AnswerCitations.stripped(answer)
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#*> -").union(.whitespaces)) }
      .first { !$0.isEmpty } ?? "保存した回答"
    let candidate = questionTitle.isEmpty ? answerTitle : questionTitle
    let title = String(candidate.prefix(48)) + (candidate.count > 48 ? "…" : "")
    var markdown = AnswerCitations.saved(answer, sources: message.sources, allowedTargets: allowed)
    var references = message.sources.enumerated().compactMap { index, source -> String? in
      guard let url = MeetingLink.url(for: source.meetingID) else { return nil }
      let name = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let label = "資料\(index + 1): \(name.isEmpty ? "無題の記録" : name)"
      return "- [\(AnswerCitations.escapeLabel(label))](\(url.absoluteString))"
    }
    let meetings = Set(message.sources.map { ArtifactSourceTarget.record(.meeting($0.meetingID)) })
    references += AnswerSourceCitation.citedTargets(in: answer, allowed: allowed).filter { !meetings.contains($0) }.enumerated().map { index, target in
      "- [出典\(index + 1): \(target.label)](\(AnswerSourceCitation.url(for: target).absoluteString))"
    }
    if !references.isEmpty {
      markdown += "\n\n## 参照した情報\n\n" + references.joined(separator: "\n")
      markdown += "\n\nリンクは、元の記録がある端末のMemoraで開けます。"
    }
    return MemoraDocument(title: title, kind: .document, markdown: markdown,
      sourceProjectFileIDs: provenance?.projectSources.map(\.id), sourceRecordIDs: message.sources.map(\.meetingID), provenance: provenance)
  }
}
