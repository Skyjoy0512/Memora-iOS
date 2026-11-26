import Foundation

/// Synthetic relevance judgments for the real project index and context builder.
@main
struct ProjectLongitudinalChecks {
  typealias Target = ProjectCitation.Target
  typealias Context = ProjectContextBuilder.Context

  private struct Query {
    var name: String
    var question: String
    var relevant: Set<Target>
    var observesExtraEvidence = false
  }

  private struct Corpus {
    let alpha = uuid(1)
    let beta = uuid(2)
    let initial = meeting(3, date: "2026-08-18T03:00:00Z", time: 35,
      title: "公開判定の初回会議", text: "公開判定の判断基準は承認者一名とする。当初案として承認した。")
    let revised = meeting(4, date: "2026-11-05T03:00:00Z", time: 220,
      title: "公開判定の改定会議", text: "公開判定の判断基準を承認者二名へ改定した。単独承認は廃止する。改定の理由は誤操作の防止。")
    let audit = ProjectEvidenceInput(target: .source(uuid(5)), title: "監査手順",
      blocks: [.init(text: "監査手順は監査票に変更履歴を添付し、監査責任者が照合する。", page: 7)])
    let task = ProjectEvidenceInput(target: .task(uuid(6)), title: "署名鍵の棚卸し",
      blocks: [.init(text: "署名鍵の棚卸しを担当者が完了させる。")])
    let restricted = meeting(7, date: "2026-11-06T03:00:00Z", time: 98,
      title: "非公開の公開判定", text: "公開判定の判断基準は赤色の管理コード。プロジェクト内の閲覧制限付き記録。")
    let otherProject = meeting(8, date: "2026-11-07T03:00:00Z", time: 60,
      title: "公開判定の改定会議", text: "公開判定の判断基準は別の手順。別プロジェクトだけに所属する。")
    let unrelated = (9...56).map { index in
      ProjectEvidenceInput(target: .document(uuid(index)), title: "施設備品一覧 (index)",
        blocks: [.init(text: "施設管理の備品は机、椅子、画鋲および傘立て。棚番は (index)。")])
    }

    var allowed: [ProjectEvidenceInput] { [initial, revised, audit, task] + unrelated }
    var queries: [Query] {
      [
        Query(name: "longitudinal", question: "公開判定の判断基準は当初から現在までどう変わりましたか？",
          relevant: [initial.target, revised.target]),
        Query(name: "cross-source", question: "公開判定の判断基準と監査手順を教えてください。",
          relevant: [initial.target, revised.target, audit.target]),
        Query(name: "task", question: "署名鍵の棚卸しはありますか？", relevant: [task.target]),
        Query(name: "unknown", question: "火星探査機の推進方式は何ですか？", relevant: []),
        Query(name: "date-specific", question: "記録日\(dayLabel(revised.recordedAt!))の公開判定の判断基準は何ですか？",
          relevant: [revised.target]),
        Query(name: "date-only", question: "記録日: \(dayLabel(revised.recordedAt!))", relevant: [revised.target]),
        Query(name: "unqualified-date", question: "\(dayLabel(revised.recordedAt!))の公開判定の判断基準は何ですか？",
          relevant: [revised.target], observesExtraEvidence: true)
      ]
    }
  }

  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let file = root.appendingPathComponent("project-longitudinal.sqlite")
    let index = ProjectSearchIndex(fileURL: file)
    let corpus = Corpus()
    let question = corpus.queries[0].question
    let budget = 560

    // Prime the same database with another project's duplicate title, and with
    // a subsequently revoked record in the requested project.
    _ = try await index.retrieve(question: question, projectID: corpus.beta, inputs: [corpus.otherProject])
    _ = try await index.retrieve(question: question, projectID: corpus.alpha, inputs: corpus.allowed + [corpus.restricted])
    let clock = ContinuousClock()
    var warmSamples: [Double] = []
    var retrievedTotal = 0
    var relevantTotal = 0
    var judgmentTotal = 0
    for query in corpus.queries {
      let start = clock.now
      let context = try await retrieve(index, question: query.question, project: corpus.alpha, inputs: corpus.allowed, budget: budget)
      let latency = milliseconds(start.duration(to: clock.now))
      let retrieved = Set(context.used.map(\.target))
      let hits = query.relevant.intersection(retrieved).count
      let misses = query.relevant.subtracting(retrieved).count
      let unrelated = retrieved.subtracting(query.relevant).count
      retrievedTotal += retrieved.count
      relevantTotal += hits
      judgmentTotal += query.relevant.count
      print(String(format: "%@ relevant=%d missed=%d unrelated=%d sources=%d excerpts=%d characters=%d latency=%.2fms",
        query.name, hits, misses, unrelated, retrieved.count, context.used.count, context.text.count, latency))
      precondition(misses == 0, "Missing fixture evidence for \(query.name)")
      // An unqualified date may refer to a deadline or an event discussed
      // in another meeting. Only the explicit record day narrows those rows.
      if !query.observesExtraEvidence {
        precondition(unrelated == 0, "Unrelated evidence for \(query.name)")
      }
      for _ in 0..<10 {
        let start = clock.now
        let repeated = try await retrieve(index, question: query.question, project: corpus.alpha, inputs: corpus.allowed, budget: budget)
        warmSamples.append(milliseconds(start.duration(to: clock.now)))
        precondition(context.text == repeated.text, "Evidence or numbering changed on an identical snapshot")
      }
    }
    print("Fixture precision \(relevantTotal)/\(retrievedTotal), recall \(relevantTotal)/\(judgmentTotal)")
    let samples = warmSamples.sorted()
    print(String(format: "warm FTS5 + context (%d samples, %d sources): p50=%.2fms p95=%.2fms",
      samples.count, corpus.allowed.count, samples[samples.count / 2], samples[Int(ceil(0.95 * Double(samples.count))) - 1]))

    let baseline = try await retrieve(index, question: question, project: corpus.alpha, inputs: corpus.allowed, budget: budget)
    precondition(baseline.text.contains("録音内 35秒") && baseline.text.contains("録音内 220秒"))
    precondition(baseline.text.components(separatedBy: "記録日 ").count == 3)
    precondition(ProjectContextBuilder.cited("【資料1】【資料1】【資料0】【資料999】", from: baseline.used) == [baseline.used[0]])
    let tiny = try await retrieve(index, question: question, project: corpus.alpha, inputs: corpus.allowed, budget: 1)
    precondition(tiny.used.isEmpty && tiny.text.isEmpty)

    var edited = corpus.revised
    edited.recordedAt = date("2026-11-08T03:00:00Z")
    var current = corpus.allowed.map { $0.target == edited.target ? edited : $0 }
    let dateUpdate = try await retrieve(index, question: question, project: corpus.alpha, inputs: current, budget: budget)
    precondition(dateUpdate.used.contains { $0.target == edited.target && $0.recordedAt == edited.recordedAt && $0.time == 220 })
    precondition(!dateUpdate.used.contains { $0.target == edited.target && $0.recordedAt == corpus.revised.recordedAt })
    let oldDay = try await retrieve(index, question: "記録日\(dayLabel(corpus.revised.recordedAt!))", project: corpus.alpha,
      inputs: current, budget: budget)
    let newDay = try await retrieve(index, question: "記録日\(dayLabel(edited.recordedAt!))", project: corpus.alpha,
      inputs: current, budget: budget)
    precondition(oldDay.used.isEmpty && newDay.used.map(\.target) == [edited.target])
    edited.blocks = [.init(text: "公開判定の判断基準は承認者三名に変更した。二名の案は廃止する。", time: 315)]
    current = current.map { $0.target == edited.target ? edited : $0 }
    let revision = try await retrieve(index, question: question, project: corpus.alpha, inputs: current, budget: budget)
    precondition(revision.used.contains { $0.target == edited.target && $0.excerpt.contains("承認者三名") && $0.time == 315 })
    precondition(!revision.text.contains("承認者二名へ改定") && !revision.text.contains("録音内 220秒"))

    current.removeAll { $0.target == corpus.initial.target }
    let movedOut = try await retrieve(index, question: question, project: corpus.alpha, inputs: current, budget: budget)
    precondition(!movedOut.used.contains { $0.target == corpus.initial.target })
    let movedIn = try await retrieve(index, question: question, project: corpus.beta, inputs: [corpus.initial, corpus.otherProject], budget: budget)
    precondition(movedIn.used.contains { $0.target == corpus.initial.target })

    current.removeAll { $0.target == corpus.revised.target }
    let afterDelete = try await retrieve(index, question: question, project: corpus.alpha, inputs: current, budget: budget)
    precondition(afterDelete.used.isEmpty && afterDelete.text.isEmpty)
    let reopened = ProjectSearchIndex(fileURL: file)
    let afterReopen = try await retrieve(reopened, question: question, project: corpus.alpha, inputs: current, budget: budget)
    precondition(afterReopen.used.isEmpty && afterReopen.text.isEmpty)

    // The builder independently filters supplied chunks even if another
    // layer holds an older or foreign result.
    let originalChunks = ProjectContextBuilder.split(corpus.initial.blocks[0].text, projectID: corpus.alpha,
      target: corpus.initial.target, title: corpus.initial.title)
    let foreignChunks = ProjectContextBuilder.split(corpus.otherProject.blocks[0].text, projectID: corpus.beta,
      target: corpus.otherProject.target, title: corpus.otherProject.title)
    let guarded = ProjectContextBuilder.build(question: question, projectID: corpus.alpha,
      chunks: originalChunks + foreignChunks, allowed: [corpus.otherProject.target], characterBudget: budget)
    precondition(guarded.used.isEmpty && guarded.text.isEmpty)
    print("ProjectLongitudinalChecks: passed (host retrieval and citations; no inference, production access-policy or device validation)")
  }

  private static func retrieve(_ index: ProjectSearchIndex, question: String, project: UUID,
                               inputs: [ProjectEvidenceInput], budget: Int) async throws -> Context {
    let allowed = Set(inputs.map(\.target))
    let chunks = try await index.retrieve(question: question, projectID: project, inputs: inputs)
    precondition(chunks.allSatisfy { $0.projectID == project && allowed.contains($0.target) })
    let context = ProjectContextBuilder.build(question: question, projectID: project, chunks: chunks,
      allowed: allowed, characterBudget: budget)
    precondition(context.text.count <= budget && context.used.count <= 8)
    let byTarget = Dictionary(uniqueKeysWithValues: inputs.map { ($0.target, $0) })
    for citation in context.used {
      guard let source = byTarget[citation.target] else { preconditionFailure("Citation outside the current snapshot") }
      precondition(source.recordedAt == citation.recordedAt)
      precondition(source.blocks.contains {
        $0.text.contains(citation.excerpt) && $0.time == citation.time && $0.page == citation.page
      }, "Citation does not match original text and location")
    }
    return context
  }

  private static func uuid(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "8EF9AC00-0000-0000-0000-%012d", value))!
  }

  private static func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  private static func dayLabel(_ date: Date) -> String {
    let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    return "\(parts.year!)年\(parts.month!)月\(parts.day!)日"
  }

  private static func meeting(_ id: Int, date recordedAt: String, time: TimeInterval,
                              title: String, text: String) -> ProjectEvidenceInput {
    ProjectEvidenceInput(target: .meeting(uuid(id)), title: title, blocks: [.init(text: text, time: time)],
      recordedAt: date(recordedAt))
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let time = duration.components
    return Double(time.seconds) * 1_000 + Double(time.attoseconds) / 1e15
  }
}
