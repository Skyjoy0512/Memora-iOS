import Foundation

/// The structured evidence a presentation is built from. It keeps the original
/// source identity beside every fact, so a later summary cannot quietly turn a
/// proposal into a decision or drop the record a number came from.
struct PresentationEvidencePack: Codable, Hashable, Sendable {
  var purpose = ""
  var audience = ""
  var decisionRequired = ""
  var projectContext: [String] = []
  var background: [String] = []
  var timeline: [TimelineEntry] = []
  var decisions: [DecisionEntry] = []
  var stakeholders: [Stakeholder] = []
  var keyFacts: [Fact] = []
  var metrics: [Metric] = []
  var contradictions: [String] = []
  var risks: [String] = []
  var unconfirmed: [String] = []
  var previousFinalDeck: SourceReference?
  var relatedSources: [SourceReference] = []
  var permissions: [SourceReference] = []
  var versions: [String] = []
  var estimatedTokens = 0
  var generatedAt = Date.now

  enum Stance: String, Codable, Hashable, Sendable {
    case fact, opinion, hypothesis
    var label: String {
      switch self {
      case .fact: "事実"
      case .opinion: "意見"
      case .hypothesis: "仮説"
      }
    }
  }

  enum Confidence: String, Codable, Hashable, Sendable {
    case confirmed, reported, unverified
    var label: String {
      switch self {
      case .confirmed: "確認済み"
      case .reported: "記録あり"
      case .unverified: "未確認"
      }
    }
  }

  struct SourceReference: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: SourceKind
    var title: String
    var date: Date?
    var updatedAt: Date?
    var version: String?
    var isFinal: Bool
    var permission: Permission

    var summary: String {
      var parts = ["[\(id)] \(kind.label): \(title)"]
      if let date { parts.append(date.formatted(date: .numeric, time: .omitted)) }
      if let version { parts.append("版\(version)") }
      if isFinal { parts.append("最終版") }
      parts.append(permission.label)
      return parts.joined(separator: " / ")
    }
  }

  struct TimelineEntry: Codable, Hashable, Sendable {
    var date: Date
    var title: String
    var sourceID: String
  }

  struct DecisionEntry: Codable, Hashable, Sendable {
    var id: String
    var subject: String
    var statement: String
    var date: Date
    var decidedBy: String?
    var meetingTitle: String?
    var status: DecisionStatus
    var supersedes: String?
    var rationale: String?
    var dissent: String?
    var unresolved: String?
    var sourceID: String
    var isCurrent: Bool
  }

  struct Stakeholder: Codable, Hashable, Sendable {
    var name: String
    var role: String?
    var relatedSourceIDs: [String] = []
    var statements: [String] = []
  }

  struct Fact: Codable, Hashable, Sendable {
    var text: String
    var sourceID: String
    var date: Date?
    var stance: Stance
    var confidence: Confidence
    var locator: String?
  }

  struct Metric: Codable, Hashable, Sendable {
    var name: String
    var value: String
    var unit: String
    var period: String?
    var sourceID: String
  }

  /// One fact is a check on the deck, never permission to read its source.
  var allowedFacts: [Fact] { keyFacts.filter { _ in true } }
}

enum PresentationSourceKind: String, Codable, Hashable, Sendable {
  case record, transcript, summary, journal, task, project, document, web, person, memory, previousDeck, chat
  var label: String {
    switch self {
    case .record: "会議"
    case .transcript: "文字起こし"
    case .summary: "要約"
    case .journal: "ジャーナル"
    case .task: "タスク"
    case .project: "プロジェクト"
    case .document: "資料"
    case .web: "Web資料"
    case .person: "人物"
    case .memory: "長期メモリ"
    case .previousDeck: "前回資料"
    case .chat: "過去の会話"
    }
  }
}

typealias SourceKind = PresentationSourceKind

enum PresentationSourcePermission: String, Codable, Hashable, Sendable {
  case allowed, denied, unknown
  var label: String {
    switch self {
    case .allowed: "参照可"
    case .denied: "参照不可"
    case .unknown: "許可未確認"
    }
  }
}

typealias Permission = PresentationSourcePermission

enum PresentationDecisionStatus: String, Codable, Hashable, Sendable {
  case proposed, approved, changed, withdrawn, cancelled, completed, open
  var label: String {
    switch self {
    case .proposed: "提案"
    case .approved: "承認"
    case .changed: "変更"
    case .withdrawn: "撤回"
    case .cancelled: "中止"
    case .completed: "完了"
    case .open: "未決"
    }
  }
  /// A decision that still governs today. A withdrawn or cancelled one does not.
  var isEffective: Bool { self == .approved || self == .changed || self == .completed || self == .open }
}

typealias DecisionStatus = PresentationDecisionStatus

/// One piece of evidence supplied to the builder. The builder never reads a
/// store itself, so a caller must pass only what the person allows.
struct PresentationEvidenceSource: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var kind: SourceKind
  var title: String
  var text: String
  var date: Date?
  var updatedAt: Date?
  var permission: Permission = .unknown
  var stance: PresentationEvidencePack.Stance = .fact
  var confidence: PresentationEvidencePack.Confidence = .reported
  var locator: String?
  var version: String?
  var isFinal = false

  var reference: PresentationEvidencePack.SourceReference {
    .init(id: id, kind: kind, title: title, date: date, updatedAt: updatedAt,
      version: version, isFinal: isFinal, permission: permission)
  }
}

struct PresentationDecisionRecord: Codable, Hashable, Sendable, Identifiable {
  var id: String
  var subject: String
  var statement: String
  var date: Date
  var status: DecisionStatus
  var decidedBy: String?
  var meetingTitle: String?
  var supersedes: String?
  var rationale: String?
  var dissent: String?
  var unresolved: String?
  var sourceID: String
}

struct PresentationContextRequest: Sendable {
  var purpose = ""
  var audience = ""
  var decisionRequired = ""
  var query = ""
  var topics: [String] = []
  var projectName: String?
  var periodStart: Date?
  var periodEnd: Date?
}

enum PresentationContextBuilder {
  /// Ranks by the request's own words plus the caller's topics, keeps the
  /// recent and final material when scores tie, and drops anything not allowed
  /// for cloud use. Denied sources are never read or sent.
  static func build(
    request: PresentationContextRequest,
    sources: [PresentationEvidenceSource],
    decisions: [PresentationDecisionRecord] = [],
    characterBudget: Int
  ) -> PresentationEvidencePack {
    var pack = PresentationEvidencePack()
    pack.purpose = clipped(request.purpose, 500)
    pack.audience = clipped(request.audience, 300)
    pack.decisionRequired = clipped(request.decisionRequired, 500)
    if let projectName = request.projectName { pack.projectContext = ["対象プロジェクト: \(projectName)"] }
    if let start = request.periodStart, let end = request.periodEnd {
      pack.projectContext.append("対象期間: \(start.formatted(date: .numeric, time: .omitted)) 〜 \(end.formatted(date: .numeric, time: .omitted))")
    }

    let allowed = sources.filter { $0.permission == .allowed }
    let unknown = sources.filter { $0.permission == .unknown }
    let denied = sources.filter { $0.permission == .denied }
    pack.relatedSources = allowed.map(\.reference)
    pack.permissions = denied.map(\.reference) + unknown.map(\.reference)
    pack.unconfirmed.append(contentsOf: denied.map { "\($0.title) は参照が許可されていないため資料に使いません。" })
    pack.unconfirmed.append(contentsOf: unknown.map { "\($0.title) は参照許可が未確認のため、クラウド資料では使いません。" })

    let terms = searchTerms(request)
    let ranked = allowed.enumerated().map { index, source -> (Int, PresentationEvidenceSource, Int) in
      let text = source.title + " " + source.text
      let score = terms.reduce(0) { $0 + occurrences(of: $1, in: text) }
        + (source.isFinal ? 4 : 0)
        + (source.kind == .previousDeck ? 6 : 0)
      return (index, source, score)
    }.sorted { left, right in
      if left.2 != right.2 { return left.2 > right.2 }
      let leftDate = left.1.date ?? .distantPast
      let rightDate = right.1.date ?? .distantPast
      if leftDate != rightDate { return leftDate > rightDate }
      return left.0 < right.0
    }

    var seen = Set<String>()
    var used = 0
    let previous = ranked.first { $0.1.kind == .previousDeck && $0.1.isFinal }?.1
      ?? ranked.first { $0.1.kind == .previousDeck }?.1
    if let previous {
      pack.previousFinalDeck = previous.reference
      if previous.isFinal {
        pack.background.append("前回の最終提出版: \(previous.title)")
      } else {
        pack.unconfirmed.append("最終提出版を特定できませんでした。\(previous.title) は草稿として扱います。")
      }
    }

    for (_, source, score) in ranked {
      let isPinned = source.id == previous?.id
      guard score > 0 || isPinned else { continue }
      let normalized = normalize(source.text)
      guard seen.insert(normalized.prefix(400).description).inserted else { continue }
      let remaining = characterBudget - used
      guard remaining > 250 else { break }
      let excerpt = window(source.text, around: terms, limit: min(1_200, remaining - 120))
      guard !excerpt.isEmpty else { continue }
      let fact = PresentationEvidencePack.Fact(text: excerpt, sourceID: source.id,
        date: source.date, stance: source.stance, confidence: source.confidence, locator: source.locator)
      pack.keyFacts.append(fact)
      used += excerpt.count
      if let date = source.date {
        pack.timeline.append(.init(date: date, title: source.title, sourceID: source.id))
      }
      extractMetrics(source).forEach { pack.metrics.append($0) }
      extractRisks(source.text).forEach { pack.risks.append("\(source.title): \($0)") }
      if source.kind == .person {
        pack.stakeholders.append(.init(name: source.title, role: nil,
          relatedSourceIDs: [source.id], statements: [excerpt]))
      }
    }
    pack.timeline.sort { $0.date < $1.date }
    pack.risks = unique(pack.risks).prefix(12).map { $0 }

    let allowedDecisionSourceIDs = Set(allowed.map(\.id))
    let relevantDecisions = decisions.filter { allowedDecisionSourceIDs.contains($0.sourceID) }
    pack.decisions = resolveDecisions(relevantDecisions)
    for decision in pack.decisions where decision.decidedBy != nil {
      let name = decision.decidedBy!
      if let index = pack.stakeholders.firstIndex(where: { $0.name == name }) {
        pack.stakeholders[index].statements.append("\(decision.date.formatted(date: .numeric, time: .omitted)) \(decision.statement)")
      } else {
        pack.stakeholders.append(.init(name: name, role: "決定者", relatedSourceIDs: [decision.sourceID],
          statements: ["\(decision.date.formatted(date: .numeric, time: .omitted)) \(decision.statement)"]))
      }
    }
    for decision in pack.decisions where decision.decidedBy == nil {
      pack.unconfirmed.append("「\(decision.statement)」の決定者が記録から確認できません。")
    }
    if pack.decisions.contains(where: { $0.status == .withdrawn || $0.status == .cancelled }) {
      pack.background.append("撤回・中止された決定は現在の決定として扱っていません。")
    }

    pack.contradictions = contradictions(in: pack.keyFacts)
    pack.background.append(contentsOf: pack.keyFacts.prefix(3).map { $0.text })
    pack.background = unique(pack.background).prefix(6).map { $0 }
    if request.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      pack.unconfirmed.append("資料の目的が未指定です。")
    }
    if request.audience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      pack.unconfirmed.append("対象読者が未指定です。")
    }
    if request.decisionRequired.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      pack.unconfirmed.append("判断してほしいことが未指定です。")
    }
    pack.unconfirmed = unique(pack.unconfirmed).prefix(20).map { $0 }
    pack.versions = allowed.compactMap { source in
      guard let version = source.version else { return nil }
      return "\(source.title): \(version)\(source.isFinal ? "（最終）" : "")"
    }
    pack.estimatedTokens = TokenBudgetManager.estimatedTokens(pack.render())
    return pack
  }

  /// Groups by subject and lets the newest effective decision stand. A later
  /// withdrawal or cancellation hides the old decision from "current" but the
  /// history stays in the same list with `isCurrent == false`.
  static func resolveDecisions(_ records: [PresentationDecisionRecord]) -> [PresentationEvidencePack.DecisionEntry] {
    let grouped = Dictionary(grouping: records) { normalize($0.subject).prefix(60).description }
    var result: [PresentationEvidencePack.DecisionEntry] = []
    for (_, group) in grouped {
      let ordered = group.sorted { left, right in
        if left.date != right.date { return left.date < right.date }
        return left.id < right.id
      }
      let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
      // The newest record decides whether the subject has a current decision;
      // an earlier approved record only stands if nothing later withdrew it.
      var latestEffective: PresentationDecisionRecord?
      var superseded: [PresentationDecisionRecord] = []
      for record in ordered {
        if record.status.isEffective {
          if let previous = latestEffective {
            superseded.append(previous)
            _ = byID[previous.id]
          }
          latestEffective = record
        } else {
          if let previous = latestEffective { superseded.append(previous) }
          latestEffective = nil
        }
      }
      for record in ordered {
        let isCurrent = latestEffective?.id == record.id
        result.append(.init(id: record.id, subject: record.subject, statement: record.statement,
          date: record.date, decidedBy: record.decidedBy, meetingTitle: record.meetingTitle,
          status: record.status, supersedes: record.supersedes, rationale: record.rationale,
          dissent: record.dissent, unresolved: record.unresolved, sourceID: record.sourceID,
          isCurrent: isCurrent))
      }
      _ = superseded
    }
    return result.sorted { $0.date > $1.date }
  }

  // MARK: - Text helpers

  static func normalize(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
      .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
  }

  static func terms(_ text: String) -> Set<String> {
    let characters = Array(normalize(text).filter { $0.isLetter || $0.isNumber })
    guard characters.count >= 2 else { return Set(characters.map(String.init)) }
    return Set((0..<(characters.count - 1)).map { String(characters[$0...($0 + 1)]) })
  }

  static func searchTerms(_ request: PresentationContextRequest) -> [String] {
    let base = [request.query, request.purpose, request.decisionRequired].joined(separator: " ")
    var result = terms(base)
    result.formUnion(request.topics.flatMap { terms($0) })
    result.formUnion(request.topics.map { normalize($0) })
    return Array(result).filter { !$0.isEmpty }.sorted()
  }

  static func occurrences(of term: String, in text: String) -> Int {
    guard !term.isEmpty else { return 0 }
    return normalize(text).components(separatedBy: term).count - 1
  }

  static func window(_ text: String, around terms: [String], limit: Int) -> String {
    guard limit > 0, !text.isEmpty else { return "" }
    let normalized = normalize(text)
    guard normalized.count > limit else { return normalized }
    let characters = Array(normalized)
    var bestStart = 0
    var bestHits = -1
    var start = 0
    let stride = max(1, limit / 2)
    while start < characters.count {
      let end = min(characters.count, start + limit)
      let slice = String(characters[start..<end])
      let hits = terms.reduce(0) { $0 + occurrences(of: $1, in: slice) }
      if hits > bestHits { bestHits = hits; bestStart = start }
      if end == characters.count { break }
      start += stride
    }
    return String(characters[bestStart..<min(characters.count, bestStart + limit)])
  }

  private static let numberExpression = try? NSRegularExpression(pattern: #"(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?"#)

  static func numbers(in text: String) -> Set<String> {
    guard let expression = numberExpression else { return [] }
    let normalized = text.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    return Set(expression.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
      Range($0.range, in: normalized).map { String(normalized[$0]).replacingOccurrences(of: ",", with: "") }
    })
  }

  static func extractMetrics(_ source: PresentationEvidenceSource) -> [PresentationEvidencePack.Metric] {
    let lines = source.text.components(separatedBy: CharacterSet.newlines)
    var result: [PresentationEvidencePack.Metric] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !numbers(in: trimmed).isEmpty else { continue }
      let unit = ["%", "円", "件", "人", "時間", "分", "倍", "pt", "万人", "億円"].first { trimmed.contains($0) } ?? ""
      let name = trimmed.split(whereSeparator: { $0 == ":" || $0 == "：" || $0 == "は" || $0 == "が" })
        .first.map(String.init) ?? trimmed
      result.append(.init(name: clipped(name, 60), value: numbers(in: trimmed).sorted().joined(separator: ", "),
        unit: unit, period: source.date.map { $0.formatted(date: .numeric, time: .omitted) }, sourceID: source.id))
      if result.count >= 8 { break }
    }
    return result
  }

  static func extractRisks(_ text: String) -> [String] {
    let markers = ["リスク", "懸念", "課題", "遅延", "未決", "未解決", "失敗", "障害", "不足"]
    return text.components(separatedBy: CharacterSet.newlines).map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { line in
      !line.isEmpty && markers.contains { line.contains($0) }
    }.prefix(3).map { clipped($0, 220) }
  }

  static func contradictions(in facts: [PresentationEvidencePack.Fact]) -> [String] {
    var result: [String] = []
    for i in facts.indices {
      let left = facts[i]
      let leftTerms = terms(left.text)
      let leftNumbers = numbers(in: left.text)
      guard !leftNumbers.isEmpty else { continue }
      for j in (i + 1)..<facts.count {
        let right = facts[j]
        let shared = leftTerms.intersection(terms(right.text)).count
        let rightNumbers = numbers(in: right.text)
        guard shared >= 6, !rightNumbers.isEmpty, leftNumbers != rightNumbers else { continue }
        result.append("\(left.sourceID) と \(right.sourceID) で数値が異なります（\(leftNumbers.sorted().joined(separator: ", ")) / \(rightNumbers.sorted().joined(separator: ", "))）。どちらが現在の値か原資料で確認してください。")
        if result.count >= 6 { return result }
      }
    }
    return result
  }

  static func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert(normalize($0)).inserted }
  }

  static func clipped(_ value: String, _ limit: Int) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
  }
}

extension PresentationEvidencePack {
  /// A compact prompt block. It keeps source IDs so the model can cite the
  /// original record instead of inventing one.
  func render() -> String {
    var lines: [String] = []
    if !purpose.isEmpty { lines.append("目的: \(purpose)") }
    if !audience.isEmpty { lines.append("読者: \(audience)") }
    if !decisionRequired.isEmpty { lines.append("判断してほしいこと: \(decisionRequired)") }
    if !projectContext.isEmpty { lines.append(contentsOf: projectContext.prefix(4)) }
    if let previousFinalDeck { lines.append("前回の最終提出版: \(previousFinalDeck.summary)") }
    if !decisions.isEmpty {
      lines.append("意思決定（現在有効なものと履歴）:")
      for decision in decisions.prefix(20) {
        lines.append("- \(decision.isCurrent ? "現行" : "履歴") \(decision.date.formatted(date: .numeric, time: .omitted)) \(decision.statement) [\(decision.status.label)] 出典: \(decision.sourceID)\(decision.decidedBy.map { " 決定者: \($0)" } ?? "")")
      }
    }
    if !timeline.isEmpty {
      lines.append("時系列:")
      for entry in timeline.prefix(20) {
        lines.append("- \(entry.date.formatted(date: .numeric, time: .omitted)) \(entry.title) [\(entry.sourceID)]")
      }
    }
    if !keyFacts.isEmpty {
      lines.append("根拠となる抜粋（原文のIDを保持。要約で数字を変えない）:")
      for fact in keyFacts.prefix(20) {
        lines.append("- [\(fact.sourceID)] (\(fact.stance.label)/\(fact.confidence.label)) \(fact.text)")
      }
    }
    if !metrics.isEmpty {
      lines.append("数値:")
      for metric in metrics.prefix(12) {
        lines.append("- \(metric.name): \(metric.value)\(metric.unit) [\(metric.sourceID)]")
      }
    }
    if !contradictions.isEmpty { lines.append("矛盾:"); lines.append(contentsOf: contradictions.map { "- \($0)" }) }
    if !risks.isEmpty { lines.append("リスク・課題:"); lines.append(contentsOf: risks.map { "- \($0)" }) }
    if !unconfirmed.isEmpty { lines.append("未確認:"); lines.append(contentsOf: unconfirmed.map { "- \($0)" }) }
    if !stakeholders.isEmpty { lines.append("関係者: " + stakeholders.prefix(10).map(\.name).joined(separator: "、")) }
    return lines.joined(separator: "\n")
  }
}
