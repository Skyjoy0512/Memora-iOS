import Foundation
import Darwin

/// Measures the real index and context builder. Gold labels are independent of
/// their scores; low quality is reported, not redefined as a passing answer.
@main
struct ProjectSearchQualityChecks {
  static func main() async throws {
    let corpusURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL))
    let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let index = ProjectSearchIndex(fileURL: directory.appendingPathComponent("quality.sqlite"))
    let alpha = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let beta = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let identifiers = Dictionary(uniqueKeysWithValues: corpus.documents.enumerated().map { offset, doc in
      (doc.id, ProjectCitation.Target.source(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!))
    })
    let names = Dictionary(uniqueKeysWithValues: identifiers.map { ($0.value, $0.key) })
    func input(_ doc: Corpus.Document) -> ProjectEvidenceInput {
      ProjectEvidenceInput(target: identifiers[doc.id]!, title: doc.title, blocks: doc.blocks.map { block in
        precondition((0...10_000).contains(block.repeatPrefix ?? 0))
        return ProjectSourceText(text: String(repeating: "定例の説明を記載しています。", count: block.repeatPrefix ?? 0) + block.text, page: block.page)
      })
    }
    let allowedDocs = corpus.documents.filter { $0.project == "alpha" && $0.allowed != false }
    let inputs = allowedDocs.map(input)
    let allowed = Set(inputs.map(\.target))
    _ = try await index.retrieve(question: "公開", projectID: beta,
      inputs: corpus.documents.filter { $0.project == "beta" }.map(input))
    var recalls: [Double] = [], reciprocalRanks: [Double] = [], precisions: [Double] = [], latencies: [Double] = []
    var firstHits = 0, irrelevant = 0, sent = 0, unknownAbstained = 0, unknownCount = 0
    let clock = ContinuousClock()
    print("Project search fixture asOf=\(corpus.asOf); IDs, text and gold labels are synthetic")
    for query in corpus.queries {
      precondition(Set(query.gold).isSubset(of: Set(allowedDocs.map(\.id))))
      let start = clock.now
      let chunks = try await index.retrieve(question: query.question, projectID: alpha, inputs: inputs)
      let context = ProjectContextBuilder.build(question: query.question, projectID: alpha, chunks: chunks,
        allowed: allowed, characterBudget: 12_000)
      let duration = start.duration(to: clock.now).components
      latencies.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
      precondition(chunks.allSatisfy { $0.projectID == alpha && allowed.contains($0.target) })
      var retrieved: [String] = []
      for source in context.used {
        let name = names[source.target]!
        let original = allowedDocs.first { $0.id == name }!
        precondition(original.blocks.contains { block in
          let full = String(repeating: "定例の説明を記載しています。", count: block.repeatPrefix ?? 0) + block.text
          return full.contains(source.excerpt) && block.page == source.page
        }, "Citation excerpt/page is not in the allowed original source")
        if !retrieved.contains(name) { retrieved.append(name) }
      }
      let top = Array(retrieved.prefix(3)), gold = Set(query.gold)
      if !gold.isEmpty {
        recalls.append(Double(gold.intersection(top).count) / Double(gold.count))
        precisions.append(Double(gold.intersection(top).count) / 3)
        let rank = retrieved.firstIndex { gold.contains($0) }
        reciprocalRanks.append(rank.map { 1 / Double($0 + 1) } ?? 0)
        if top.first.map(gold.contains) == true { firstHits += 1 }
      } else {
        unknownCount += 1
        if retrieved.isEmpty { unknownAbstained += 1 }
      }
      irrelevant += retrieved.filter { !gold.contains($0) }.count
      sent += retrieved.count
      if let excerpt = query.requiredExcerpt {
        precondition(context.used.contains { $0.excerpt.contains(excerpt) && $0.page == query.requiredPage }, "Long PDF evidence lost")
      }
      print("\(query.id): top3=\(top.joined(separator: ",")) gold=\(query.gold.joined(separator: ",")) sent=\(retrieved.count)")
      fflush(stdout)
    }
    let recall = recalls.reduce(0, +) / Double(recalls.count)
    let mrr = reciprocalRanks.reduce(0, +) / Double(reciprocalRanks.count)
    let precision = precisions.reduce(0, +) / Double(precisions.count)
    let sorted = latencies.sorted()
    let unrelatedRatio = Double(irrelevant) / Double(max(1, sent))
    print(String(format: "MEASURE hit@1=%d/%d recall@3=%.3f precision@3=%.3f MRR=%.3f unrelated-sent=%.3f no-evidence-abstain=%d/%d p50=%.2fms p95=%.2fms max=%.2fms",
      firstHits, recalls.count, recall, precision, mrr, unrelatedRatio, unknownAbstained, unknownCount,
      sorted[sorted.count / 2], sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!))
    fflush(stdout)
    if !CommandLine.arguments.contains("--measure-only") {
      precondition(firstHits == recalls.count && recall == 1, "Fixed corpus retrieval regressed")
      precondition(unknownAbstained == unknownCount && unrelatedRatio <= 0.5, "Fixed corpus evidence precision regressed")
    }
    var updated = inputs
    let release = identifiers["release"]!
    let releaseIndex = updated.firstIndex { $0.target == release }!
    updated[releaseIndex].blocks = [ProjectSourceText(text: "本番リリース日は12月2日に変更しました。")]
    let afterEdit = try await index.retrieve(question: "本番リリース", projectID: alpha, inputs: updated)
    precondition(!afterEdit.contains { $0.text.contains("11月18日") })
    let removed = identifiers["open"]!
    updated.removeAll { $0.target == removed }
    let afterDelete = try await index.retrieve(question: "未決事項", projectID: alpha, inputs: updated)
    precondition(!afterDelete.contains { $0.target == removed })
    let revoked = identifiers["budget-new"]!
    updated.removeAll { $0.target == revoked }
    let afterRevoke = try await index.retrieve(question: "予算", projectID: alpha, inputs: updated)
    precondition(!afterRevoke.contains { $0.target == revoked || $0.target == identifiers["revoked"]! })
    print("ProjectSearchQualityChecks: passed (measured real FTS5 + context, long PDF/page evidence, scoped snapshots, update/delete/revoke invalidation; metrics are not LLM answer quality)")
  }

  struct Corpus: Decodable {
    var asOf: String
    var documents: [Document]
    var queries: [Query]
    struct Document: Decodable {
      var id: String
      var project: String
      var allowed: Bool?
      var title: String
      var blocks: [Block]
    }
    struct Block: Decodable { var text: String; var page: Int?; var repeatPrefix: Int? }
    struct Query: Decodable {
      var id: String; var kind: String; var question: String; var gold: [String]
      var requiredExcerpt: String?; var requiredPage: Int?
    }
  }
}
