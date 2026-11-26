import Foundation

enum SourceEvidenceRanking {
  static func select(_ citations: [ProjectCitation], question: String, budget: Int) -> [ProjectCitation] {
    let namespace = UUID()
    let chunks = citations.map { ProjectEvidenceChunk(projectID: namespace, target: $0.target,
      title: $0.title, text: $0.excerpt, page: $0.page, time: $0.time, recordedAt: $0.recordedAt) }
    return ProjectContextBuilder.build(question: question, projectID: namespace, chunks: chunks,
      allowed: Set(citations.map(\.target)), characterBudget: budget).used
  }
}
