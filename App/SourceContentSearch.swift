import Foundation

enum SourceContentSearch {
  static func context(source: ProjectSource, question: String, budget: Int,
    index: ProjectSearchIndex = .shared
  ) async throws -> ProjectContextBuilder.Context {
    guard let reference = source.extractedTextReference else {
      return .init(text: "", used: [], matchedCount: 0)
    }
    let blocks = try await ProjectSourceTextReader.readAsync(reference)
    try Task.checkCancellation()
    let input = ProjectEvidenceInput(target: .source(source.id), title: source.title, blocks: blocks)
    // Per-source namespaces avoid replacing an actual project's shared index.
    let indexed = try await index.retrieve(question: question, projectID: source.id, inputs: [input],
      maximumCharacters: ProjectSourceTextReader.maximumBytes)
    return await Task.detached(priority: .utility) {
      ProjectContextBuilder.build(question: question, projectID: source.id, chunks: indexed,
        allowed: [.source(source.id)], characterBudget: budget,
        selectedTarget: question.isEmpty ? .source(source.id) : nil)
    }.value
  }

  static func rendered(_ context: ProjectContextBuilder.Context) -> String {
    context.used.map { citation in
      let safeTime = citation.time.flatMap { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) ? $0 : nil }
      let location = citation.page.map { "ページ\($0)" } ?? safeTime.map { "\(Int($0))秒" } ?? "原文"
      return "[\(location)] \(citation.excerpt)"
    }.joined(separator: "\n")
  }
}
