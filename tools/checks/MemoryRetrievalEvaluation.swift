import Foundation

@main
enum MemoryRetrievalEvaluation {
  struct Dataset: Decodable {
    var entries: [Entry]
    var cases: [Scenario]
  }

  struct Entry: Decodable {
    var key: String
    var text: String
    var time: TimeInterval
    var workspace: String?
    var person: UUID?
  }

  struct Scenario: Decodable {
    var label: String
    var query: String
    var expected: [String]
    var ordered: Bool?
    var workspace: String?
    var person: UUID?
    var excluding: [String]?
    var replacing: [String: String]?
  }

  static func main() throws {
    let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
    let dataset = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: fixture))
    let corpus = dataset.entries.map { entry in
      let id = UUID()
      let item = MemoryRetrievalItem(id: id, kind: .episode, text: entry.text,
        updatedAt: Date(timeIntervalSince1970: entry.time), workspaceID: entry.workspace,
        personID: entry.person, sourceID: id)
      return (key: entry.key, item: item)
    }
    let names = Dictionary(uniqueKeysWithValues: corpus.map { ($0.item.sourceID, $0.key) })
    var matchedCount = 0
    var retrievedCount = 0
    var expectedCount = 0
    let start = ContinuousClock.now
    for scenario in dataset.cases {
      let candidates = corpus.compactMap { entry -> MemoryRetrievalItem? in
        guard scenario.excluding?.contains(entry.key) != true else { return nil }
        var item = entry.item
        if let text = scenario.replacing?[entry.key] {
          item.text = text
          item.updatedAt += 1
        }
        return item
      }
      let result = try MemoryRetrievalOrchestrator.retrieve(scenario.query, candidates: candidates,
        workspaceID: scenario.workspace, personID: scenario.person)
      let keys = result.compactMap { names[$0.item.sourceID] }
      let expected = Set(scenario.expected)
      let found = Set(keys)
      precondition(keys.count == result.count && found.count == keys.count, scenario.label)
      precondition(found == expected, "\(scenario.label): expected \(scenario.expected), got \(keys)")
      if scenario.ordered == true { precondition(keys == scenario.expected, scenario.label) }
      matchedCount += found.intersection(expected).count
      retrievedCount += keys.count
      expectedCount += expected.count
    }
    print("Memory retrieval: \(dataset.cases.count) cases, precision \(matchedCount)/\(retrievedCount), recall \(matchedCount)/\(expectedCount), \(start.duration(to: .now)) (host, retrieval only)")
  }
}
