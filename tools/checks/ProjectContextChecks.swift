import Foundation

@main
struct ProjectContextChecks {
  static func main() {
    let project = UUID(), other = UUID()
    let source = ProjectCitation.Target.source(UUID())
    let secret = ProjectCitation.Target.source(UUID())
    let text = String(repeating: "箱根旅行の移動時間を短くする。", count: 100)
    let chunks = ProjectContextBuilder.split(text, projectID: project, target: source, title: "旅程", page: 2)
    precondition(chunks.count > 1 && chunks.allSatisfy { $0.text.count <= 700 && $0.page == 2 })
    let privateChunks = ProjectContextBuilder.split("機密事項", projectID: project, target: secret, title: "非公開")
    let otherChunks = ProjectContextBuilder.split("別プロジェクトの箱根旅行", projectID: other, target: source, title: "別件")
    for budget in [0, 20, 100, 500, 2_000] {
      let result = ProjectContextBuilder.build(question: "箱根の移動時間", projectID: project,
        chunks: chunks + privateChunks + otherChunks, allowed: [source], characterBudget: budget)
      precondition(result.text.count <= budget)
      precondition(!result.text.contains("機密事項") && !result.text.contains("別プロジェクト"))
      precondition(result.used.count <= 2)
      precondition(result.used.allSatisfy { $0.target == source && text.contains($0.excerpt) && $0.page == 2 })
    }
    let context = ProjectContextBuilder.build(question: "もっと短くして", projectID: project, chunks: chunks,
      allowed: [source], characterBudget: 1_000)
    precondition(!context.used.isEmpty)
    let citations = ProjectContextBuilder.cited("回答【資料1】【資料1】【資料99】", from: context.used)
    precondition(citations.count == 1 && citations[0] == context.used[0])
    let revoked = ProjectContextBuilder.build(question: "旅行", projectID: project, chunks: chunks,
      allowed: [], characterBudget: 1_000)
    precondition(revoked.used.isEmpty && revoked.text.isEmpty)
    let kana = ProjectContextBuilder.split("さくらの資料", projectID: project, target: source, title: "さくら")
    let kanaResult = ProjectContextBuilder.build(question: "さくら", projectID: project,
      chunks: kana, allowed: [source], characterBudget: 1_000)
    precondition(kanaResult.used.count == 1 && kanaResult.matchedCount == 1)
    for question in ["木星の衛星軌道", "ぬねのめも", "unrelated telescope"] {
      let unknown = ProjectContextBuilder.build(question: question, projectID: project,
        chunks: kana, allowed: [source], characterBudget: 1_000)
      precondition(unknown.used.isEmpty && unknown.matchedCount == 0)
    }
    let titleOnly = ProjectContextBuilder.split("本文は準備中", projectID: project, target: source, title: "保守契約")
    let titleResult = ProjectContextBuilder.build(question: "保守契約", projectID: project,
      chunks: titleOnly, allowed: [source], characterBudget: 1_000)
    precondition(titleResult.used.count == 1)
    let followUp = ProjectContextBuilder.build(question: "shorten that", projectID: project,
      chunks: kana, allowed: [source], characterBudget: 1_000)
    precondition(!followUp.used.isEmpty)
    let deadlines = ProjectContextBuilder.split("提出期限は金曜日", projectID: project, target: source, title: "作業")
    let paraphrase = ProjectContextBuilder.build(question: "納期は？", projectID: project,
      chunks: deadlines, allowed: [source], characterBudget: 1_000)
    precondition(paraphrase.used.count == 1)
    let selectedRead = ProjectContextBuilder.build(question: "承認について詳しく", projectID: project,
      chunks: kana + privateChunks + otherChunks, allowed: [source, secret], characterBudget: 1_000, selectedTarget: source)
    precondition(!selectedRead.used.isEmpty && selectedRead.used.allSatisfy { $0.target == source && $0.title == "さくら" })
    let revokedRead = ProjectContextBuilder.build(question: "承認について詳しく", projectID: project,
      chunks: kana, allowed: [], characterBudget: 1_000, selectedTarget: source)
    precondition(revokedRead.used.isEmpty)
    let overview = ProjectContextBuilder.build(question: "このプロジェクトの進捗をまとめて", projectID: project,
      chunks: kana + privateChunks + otherChunks, allowed: [source], characterBudget: 1_000)
    precondition(!overview.used.isEmpty && overview.used.allSatisfy { $0.target == source && $0.title == "さくら" })
    print("ProjectContextChecks: passed (chunk/page fidelity, isolation, budgets, follow-ups, citations, hiragana/title search, no-match abstention, local aliases)")
  }
}
