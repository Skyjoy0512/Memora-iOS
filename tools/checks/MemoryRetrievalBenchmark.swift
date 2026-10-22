import Foundation

@main
struct MemoryRetrievalBenchmark {
  static func main() throws {
    let count = Int(CommandLine.arguments.dropFirst().first ?? "2000") ?? 2000
    precondition((10...5_000).contains(count))
    let personID = UUID(uuidString: "00000000-0000-0000-0000-000000099999")!
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func fixtures(_ kind: MemoryRetrievalItem.Kind, offset: Int) -> [MemoryRetrievalItem] {
      (0..<count).map { index in
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", UInt64(offset + index)))!
        return MemoryRetrievalItem(id: id, kind: kind,
          text: kind == .semantic ? "文体の希望\(index) 短い文章で決定事項を説明する" : "会議番号\(index) 新規事業の提案書と開発計画の進捗を確認した",
          updatedAt: date.addingTimeInterval(Double(index)), workspaceID: index % 10 == 0 ? "business" : nil,
          personID: index % 10 == 1 ? personID : nil, sourceID: id)
      }
    }
    let memories = fixtures(.semantic, offset: 100_000)
    let episodes = fixtures(.episode, offset: 200_000)
    let questions = [("短い文章 決定事項", "新規事業 提案書"), ("文体 希望", "開発計画 進捗"), ("決定事項 説明", "会議 確認")]
    let clock = ContinuousClock()
    func milliseconds(_ start: ContinuousClock.Instant) -> Double {
      let value = start.duration(to: clock.now).components
      return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }
    var checksum: UInt64 = 14_695_981_039_346_656_037
    func consume(_ hits: [MemoryRetrievalOrchestrator.Hit]) {
      precondition(hits.count == 5 && hits.allSatisfy { $0.item.workspaceID == nil && $0.item.personID == nil })
      for hit in hits {
        for byte in (hit.item.kind.rawValue + hit.item.id.uuidString).utf8 { checksum = (checksum ^ UInt64(byte)) &* 1_099_511_628_211 }
      }
    }
    func pair(_ index: Int) throws -> Double {
      let query = questions[index % questions.count]
      let start = clock.now
      let first = try MemoryRetrievalOrchestrator.retrieve(query.0, candidates: memories, workspaceID: nil, personID: nil)
      let second = try MemoryRetrievalOrchestrator.retrieve(query.1, candidates: episodes, workspaceID: nil, personID: nil)
      let duration = milliseconds(start)
      consume(first); consume(second)
      return duration
    }
    // Both variants warm Foundation's tokenizer, not the SQLite index.
    _ = MemoryRetrievalOrchestrator.grams("日本語の分かち書き確認")
    let cold = try pair(0)
    let warm = try (0..<21).map { try pair($0) }.sorted()
    let result: [String: Any] = [
      "candidateCountPerKind": count,
      "authorizedCountPerKind": memories.filter { $0.workspaceID == nil && $0.personID == nil }.count,
      "operationsPerSample": "semantic + episode lookup; three query pairs in rotation",
      "warmSamples": warm.count, "coldPairMilliseconds": cold,
      "warmPairMedianMilliseconds": warm[warm.count / 2], "warmPairP95Milliseconds": warm[Int(Double(warm.count - 1) * 0.95)],
      "resultChecksum": String(checksum), "scopeAssertionsPassed": true
    ]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
  }
}
