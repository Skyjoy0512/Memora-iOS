import Foundation

struct ScopedAgentEvidence {
  private(set) var references: [ProjectCitation] = []
  private(set) var remainingCharacters: Int

  init(characterBudget: Int) { remainingCharacters = min(max(characterBudget, 0), 20_000) }

  mutating func register(_ citations: [ProjectCitation], allowed: Set<ProjectCitation.Target>) -> AgentToolOutcome {
    guard citations.count <= 80, citations.allSatisfy({ allowed.contains($0.target) && !$0.excerpt.isEmpty && $0.photo == nil }) else {
      return AgentToolOutcome(text: "対象範囲または資料の内容を確認できません。本文を渡していません。", isError: true)
    }
    var text = ""
    for citation in citations {
      let existing = references.firstIndex {
        $0.target == citation.target && $0.page == citation.page && $0.time == citation.time
          && $0.recordedAt == citation.recordedAt && $0.excerpt == citation.excerpt
      }
      guard existing != nil || references.count < 24 else { break }
      let number = (existing ?? references.count) + 1
      let title = String(citation.title.prefix(80))
      let page = citation.page.flatMap { $0 > 0 ? " · ページ\($0)" : nil }
      let time = citation.time.flatMap { offset -> String? in
        guard offset.isFinite, offset >= 0, offset < Double(Int.max) else { return nil }
        let label = citation.recordedAt == nil ? "" : "録音内 "
        return " · \(label)\(Int(offset))秒"
      }
      let date = citation.recordDateLabel.map { " · \($0)" } ?? ""
      let prefix = "【資料\(number)】 id=\(citation.target.identifier.uuidString) 「\(title)」\(date)\(page ?? time ?? "")\n"
      let available = remainingCharacters - text.count - prefix.count - 2
      guard available >= 30 else { break }
      var sent = citation
      sent.excerpt = String(citation.excerpt.prefix(min(700, available)))
      if existing == nil { references.append(sent) }
      text += prefix + sent.excerpt + "\n\n"
    }
    remainingCharacters -= text.count
    return text.isEmpty
      ? AgentToolOutcome(text: "参照できる本文がないか、この会話の資料・文字数上限に達しました。", isError: true)
      : AgentToolOutcome(text: text)
  }

  func target(for rawID: String, submitted: Set<ProjectCitation.Target>? = nil) -> ProjectCitation.Target? {
    guard let id = UUID(uuidString: rawID) else { return nil }
    let targets = Set(references.filter { $0.target.identifier == id }.map(\.target))
    guard targets.count == 1, let target = targets.first, submitted?.contains(target) ?? true else { return nil }
    return target
  }
}
