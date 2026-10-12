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
    print("ProjectContextChecks: passed (chunk/page fidelity, project/privacy isolation, budgets, follow-ups, citation validation)")
  }
}
