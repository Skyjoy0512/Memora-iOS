import Foundation

enum ProjectContextBuilder {
  struct Context: Sendable {
    var text: String
    var used: [ProjectCitation]
    var matchedCount: Int
  }

  static func split(_ text: String, projectID: UUID, target: ProjectCitation.Target,
                    title: String, page: Int? = nil, time: TimeInterval? = nil) -> [ProjectEvidenceChunk] {
    let characters = Array(text.prefix(200_000))
    var chunks: [ProjectEvidenceChunk] = []
    var offset = 0
    while offset < characters.count {
      let end = min(offset + 700, characters.count)
      let body = String(characters[offset..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !body.isEmpty { chunks.append(ProjectEvidenceChunk(projectID: projectID, target: target,
        title: title, text: body, page: page, time: time)) }
      if end == characters.count { break }
      offset = end - 100
    }
    return chunks
  }

  static func build(question: String, projectID: UUID, chunks: [ProjectEvidenceChunk],
                    allowed: Set<ProjectCitation.Target>, characterBudget: Int,
                    selectedTarget: ProjectCitation.Target? = nil) -> Context {
    let terms = queryGrams(question)
    let scoped = chunks.filter {
      $0.projectID == projectID && allowed.contains($0.target) && (selectedTarget == nil || $0.target == selectedTarget)
    }
    var ranked: [(Int, ProjectEvidenceChunk, Int)] = []
    var titleTerms: [String: Set<String>] = [:]
    for (index, chunk) in scoped.enumerated() {
      let counts = countedGrams(chunk.text)
      let bodyScore = terms.reduce(0) { $0 + counts[$1, default: 0] }
      let titleGrams = titleTerms[chunk.title] ?? grams(chunk.title)
      titleTerms[chunk.title] = titleGrams
      let titleScore = titleGrams.intersection(terms).count
      ranked.append((index, chunk, bodyScore * 2 + titleScore))
    }
    ranked.sort { left, right in
      left.2 == right.2 ? left.0 < right.0 : left.2 > right.2
    }
    let matched = ranked.filter { $0.2 > 0 }
    // Keep contextual follow-ups working, but an unrelated standalone question
    // must not receive arbitrary recent sources just because they exist.
    let minimumScore = max(1, (matched.first?.2 ?? 0) * 2 / 5)
    let candidates = matched.isEmpty ? (selectedTarget != nil || allowsContextFallback(question) ? ranked : []) :
      matched.filter { $0.2 >= minimumScore }
    var text = ""
    var used: [ProjectCitation] = []
    var perSource: [ProjectCitation.Target: Int] = [:]
    for (_, chunk, _) in candidates {
      guard used.count < 8, perSource[chunk.target, default: 0] < 2 else { continue }
      let safeTime = chunk.time.flatMap { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) ? $0 : nil }
      let location = chunk.page.map { " · ページ\($0)" } ?? safeTime.map { " · \(Int($0))秒" } ?? ""
      let prefix = "【資料\(used.count + 1)】 \(chunk.title.prefix(80))\(location)\n"
      let remaining = characterBudget - text.count - prefix.count - 2
      guard remaining >= 30 else { continue }
      let excerpt = String(chunk.text.prefix(min(700, remaining)))
      text += prefix + excerpt + "\n\n"
      used.append(ProjectCitation(target: chunk.target, title: chunk.title, excerpt: excerpt, page: chunk.page, time: chunk.time))
      perSource[chunk.target, default: 0] += 1
    }
    return Context(text: text, used: used, matchedCount: matched.count)
  }

  static func cited(_ answer: String, from sent: [ProjectCitation]) -> [ProjectCitation] {
    guard let expression = try? NSRegularExpression(pattern: "【資料([0-9]+)】") else { return [] }
    let range = NSRange(answer.startIndex..., in: answer)
    var indices = Set<Int>()
    for match in expression.matches(in: answer, range: range) {
      if let range = Range(match.range(at: 1), in: answer), let number = Int(answer[range]), sent.indices.contains(number - 1) {
        indices.insert(number - 1)
      }
    }
    return indices.sorted().map { sent[$0] }
  }

  static func grams(_ value: String) -> Set<String> {
    let characters = Array(value.lowercased().filter { $0.isLetter || $0.isNumber })
    guard characters.count >= 2 else { return Set(characters.map(String.init)) }
    return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
  }

  static func queryGrams(_ value: String) -> Set<String> {
    var result = informativeGrams(value)
    // A name written entirely in hiragana still needs its own search terms.
    if result.isEmpty { result = grams(value) }
    let query = value.lowercased()
    let alternatives = [
      ["期限", "納期", "締切", "締め切り"], ["予算", "費用", "見積", "支出"],
      ["公開", "リリース"], ["未決", "未解決", "未承認", "保留"], ["録音", "収録"]
    ]
    for group in alternatives where group.contains(where: { query.contains($0) }) {
      for term in group { result.formUnion(informativeGrams(term)) }
    }
    return result
  }

  private static func informativeGrams(_ value: String) -> Set<String> {
    grams(value).filter { gram in
      gram.unicodeScalars.contains { !(0x3040...0x309f).contains($0.value) }
    }
  }

  private static func countedGrams(_ value: String) -> [String: Int] {
    let characters = Array(value.lowercased().filter { $0.isLetter || $0.isNumber })
    guard characters.count >= 2 else { return Dictionary(characters.map { (String($0), 1) }, uniquingKeysWith: max) }
    var counts: [String: Int] = [:]
    for index in 0..<(characters.count - 1) {
      let gram = String(characters[index...index + 1])
      counts[gram] = min(2, counts[gram, default: 0] + 1)
    }
    return counts
  }

  static func allowsContextFallback(_ value: String) -> Bool {
    let question = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if question.isEmpty { return true }
    if ["このプロジェクト", "プロジェクト全体", "全体"].contains(where: { question.hasPrefix($0) }),
       ["要約", "まとめ", "概要", "進捗", "状況", "一覧"].contains(where: { question.contains($0) }) { return true }
    return ["短く", "もっと短く", "もう少し", "詳しく", "それ", "これ", "続け", "同じ", "要約して", "まとめて", "箇条書き", "英語に", "日本語に", "もう一度", "shorten", "make it shorter", "continue", "more detail", "summarize", "translate"].contains { question.hasPrefix($0) }
  }
}
