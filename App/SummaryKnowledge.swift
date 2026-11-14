import Foundation

/// A bounded extraction owned by a summary version, not a second record store.
/// Provenance is bound locally; model-provided IDs and quotes are untrusted.
struct SummaryKnowledge: Codable, Hashable, Sendable {
  var schemaVersion = 1
  var selectedProfileIDs: [String] = []
  var contentType: ContentType = .mixed
  var topics: [Topic] = []
  var facts: [Fact] = []
  var coverage: [Coverage] = []

  enum ContentType: String, Codable, Sendable {
    case meeting, sales, brainstorming, oneOnOne, learning, dailyLife, news, technical, document, video, mixed, unknown
  }

  enum Status: String, Codable, CaseIterable, Sendable {
    case confirmed, proposed, pending, notMentioned, uncertain, notApplicable
    var label: String {
      switch self {
      case .confirmed: "原文で確認"
      case .proposed: "提案"
      case .pending: "明示的に保留"
      case .notMentioned: "取得した原文では未言及"
      case .uncertain: "要確認"
      case .notApplicable: "対象外"
      }
    }
    var isVisible: Bool { self != .notMentioned && self != .notApplicable }
  }

  enum Category: String, Codable, CaseIterable, Sendable {
    case overview, background, purpose, keyFact, number, date, decision, rationale, alternative, rejectedOption
    case proposal, agreement, disagreement, issue, risk, constraint, dependency, action, owner, due, openQuestion, entity
    var label: String {
      switch self {
      case .overview: "概要"
      case .background: "背景"
      case .purpose: "目的"
      case .keyFact: "重要な事実"
      case .number: "数値・単位"
      case .date: "日付"
      case .decision: "決定"
      case .rationale: "判断理由"
      case .alternative: "選択肢"
      case .rejectedOption: "見送った案"
      case .proposal: "提案"
      case .agreement: "合意"
      case .disagreement: "反対意見"
      case .issue: "課題"
      case .risk: "リスク"
      case .constraint: "制約"
      case .dependency: "依存関係"
      case .action: "行動"
      case .owner: "担当者"
      case .due: "期限"
      case .openQuestion: "未解決事項"
      case .entity: "人物・組織"
      }
    }
  }

  enum Origin: String, Codable, Sendable { case generated, user }

  struct Topic: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
  }

  struct Fact: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var category: Category
    var content: String
    var status: Status
    var relatedTopicID: String?
    var relatedFactIDs: [String]?
    var sourceReferences: [Reference]?
    var speakerIDs: [String]?
    var temporalContext: String?
    var origin: Origin?
  }

  struct Reference: Codable, Hashable, Sendable {
    var sourceSegmentID: String
    var quote: String
    var page: Int?
  }

  struct Coverage: Codable, Hashable, Sendable {
    var aspect: String
    var status: Status
  }

  init(selectedProfileIDs: [String] = [], contentType: ContentType = .mixed,
       topics: [Topic] = [], facts: [Fact] = [], coverage: [Coverage] = []) {
    self.selectedProfileIDs = selectedProfileIDs
    self.contentType = contentType
    self.topics = topics
    self.facts = facts
    self.coverage = coverage
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, selectedProfileIDs, contentType, topics, facts, coverage }

  init(from decoder: Decoder) throws {
    self.init()
    guard let values = try? decoder.container(keyedBy: CodingKeys.self) else { return }
    schemaVersion = (try? values.decode(Int.self, forKey: .schemaVersion)) ?? 1
    selectedProfileIDs = Array(((try? values.decode([String].self, forKey: .selectedProfileIDs)) ?? []).prefix(3))
    contentType = (try? values.decode(ContentType.self, forKey: .contentType)) ?? .unknown
    topics = Array(((try? values.decode([Recoverable<Topic>].self, forKey: .topics)) ?? []).compactMap(\.value).prefix(64))
    facts = Array(((try? values.decode([Recoverable<Fact>].self, forKey: .facts)) ?? []).compactMap(\.value).prefix(256))
    coverage = Array(((try? values.decode([Recoverable<Coverage>].self, forKey: .coverage)) ?? []).compactMap(\.value).prefix(64))
  }

  private struct Recoverable<Value: Decodable>: Decodable {
    var value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
  }

  /// Validation removes unresolvable references rather than fabricating proof.
  /// It cannot prove that a paraphrase follows logically from a valid quote.
  func validated(allowedProfiles: Set<String>, verify: (Reference) -> Bool) -> Self {
    guard schemaVersion == 1 else { return Self() }
    var result = self
    result.schemaVersion = 1
    var profileIDs = Set<String>()
    result.selectedProfileIDs = Array(selectedProfileIDs.filter { allowedProfiles.contains($0) && profileIDs.insert($0).inserted }.prefix(3))
    var topicIDs = Set<String>()
    result.topics = Array(topics.filter { !$0.id.isEmpty && !$0.title.isEmpty && topicIDs.insert($0.id).inserted }.prefix(64))
    var factIDs = Set<String>()
    var contentKeys = Set<String>()
    result.facts = Array(facts.filter {
      !$0.id.isEmpty && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        $0.content.count <= 4_000 && factIDs.insert($0.id).inserted &&
        contentKeys.insert($0.category.rawValue + ":" + $0.status.rawValue + ":" + $0.content).inserted
    }.prefix(256))
    factIDs = Set(result.facts.map(\.id))
    for index in result.facts.indices {
      if let topic = result.facts[index].relatedTopicID, !topicIDs.contains(topic) { result.facts[index].relatedTopicID = nil }
      result.facts[index].relatedFactIDs = result.facts[index].relatedFactIDs.map { Array($0.filter { factIDs.contains($0) }.prefix(16)) }
      var references = Set<Reference>()
      result.facts[index].sourceReferences = (result.facts[index].sourceReferences ?? [])
        .filter { references.insert($0).inserted && verify($0) }.prefix(8).map { reference in
          var reference = reference
          reference.page = nil // Page labels come from the local original, not the model.
          return reference
        }
      if !(facts.first { $0.id == result.facts[index].id }?.sourceReferences ?? []).isEmpty,
         result.facts[index].sourceReferences?.isEmpty == true {
        result.facts[index].status = .uncertain
      }
      if !result.facts[index].status.isVisible { result.facts[index].sourceReferences = [] }
    }
    result.coverage = Array(coverage.filter { !$0.aspect.isEmpty && $0.aspect.count <= 120 }.prefix(64))
    return result
  }

  /// Retrieval considers only query-related facts that are not already in the
  /// document. No coverage placeholders or raw extraction JSON enter context.
  func relevantFacts(to words: [String], excluding document: String, limit: Int = 8) -> [Fact] {
    facts.filter { fact in
      fact.status.isVisible && !document.contains(fact.content) &&
        words.contains { !$0.isEmpty && fact.content.localizedCaseInsensitiveContains($0) }
    }.prefix(max(0, min(limit, 8))).map { $0 }
  }
}
