import Foundation

@main struct AttachmentCitationChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AIAttachments")
    let first = AIAttachment(id: UUID(), name: "First PDF", url: root.appendingPathComponent("first.pdf"))
    let second = AIAttachment(id: UUID(), name: "Second audio", url: root.appendingPathComponent("second.m4a"))
    var attachment = first
    attachment.append(second)
    let early = (1...23).map { ProjectSourceText(text: "Background material \($0)", page: $0) }
    let late = ProjectSourceText(text: "SAPPHIRE QUARTZ 2468 is on page twenty-four", page: 24)
    await SourceExtractionCache.shared.set(first.url, blocks: early + [late])
    await SourceExtractionCache.shared.set(second.url, blocks: [.init(text: "SAPPHIRE QUARTZ 2468 audio evidence", time: 72.5)])
    let prepared = await AIAttachmentText.prepare(attachment, question: "SAPPHIRE QUARTZ 2468", maximumCharacters: 700)
    let text = prepared.text ?? ""
    precondition(prepared.failure == nil && text.count <= 700)
    let citations = prepared.attachmentCitations
    precondition(citations.count >= 2 && Set(citations.map(\.number)).count == citations.count)
    precondition(citations.contains { $0.file.id == first.id && $0.page == 24 && late.text.hasPrefix($0.excerpt) })
    precondition(citations.contains { $0.file.id == second.id && $0.time == 72.5 && $0.page == nil })
    precondition(citations.allSatisfy { $0.isValid && text.contains($0.contextText) && $0.file.additionalFiles == nil })
    precondition(AIAttachmentCitation.retained(citations, in: text) == citations)
    if let last = citations.last, let range = text.range(of: last.contextText) {
      let cut = String(text[..<range.lowerBound]) + last.marker + "\n" + String(last.excerpt.prefix(3))
      precondition(!AIAttachmentCitation.retained(citations, in: cut).contains(last))
      precondition(AIAttachmentCitation.retained([last], in: last.marker).isEmpty)
    }
    let allCuts = (0...text.count).map { String(text.prefix($0)) }
    for cut in allCuts {
      let retained = AIAttachmentCitation.retained(citations, in: cut)
      precondition(retained.allSatisfy { cut.contains($0.contextText) })
    }
    let reference = AIAttachmentFileReference(first)!
    precondition(AIAttachmentCitation(number: 1, file: reference, excerpt: "evidence", page: 0) == nil)
    precondition(AIAttachmentCitation(number: 65, file: reference, excerpt: "evidence") == nil)
    precondition(AIAttachmentCitation(number: 1, file: reference, excerpt: " ") == nil)
    precondition(AIAttachmentCitation(number: 1, file: reference, excerpt: "evidence", time: -.infinity) == nil)
    precondition(AIAttachmentCitation(number: 1, file: AIAttachmentFileReference(attachment)!, excerpt: "evidence") == nil)
    let bytes = try JSONEncoder().encode(citations)
    let decoded = try JSONDecoder().decode([AIAttachmentCitation].self, from: bytes)
    precondition(decoded == citations)
    let decomposed = AIAttachmentCitation(number: 1, file: reference, excerpt: "e\u{301}")!
    precondition(AIAttachmentCitation.retained([decomposed], in: decomposed.marker + "\n\u{e9}").isEmpty)
    var bad = citations[0]
    bad.file.additionalFiles = [AIAttachmentFileReference(second)!]
    let badData = try JSONEncoder().encode(bad)
    precondition((try? JSONDecoder().decode(AIAttachmentCitation.self, from: badData)) == nil)
    let unicode = String(repeating: "🧑🏽‍💻あe\u{301}", count: 1_000)
    let selection = SourceTextSelection.selectedBlocks(blocks: [.init(text: unicode, page: 31)], question: "",
      budget: 20_000, maximumBlockUTF8Bytes: 8_000)
    precondition(selection.isExcerpt && selection.blocks.count == 1)
    precondition(selection.blocks[0].text.utf8.count <= 8_000 && unicode.hasPrefix(selection.blocks[0].text))
    precondition(selection.blocks[0].page == 31)
    for budget in [0, 1, 20, 100, 299, 700] {
      let bounded = await AIAttachmentText.prepare(attachment, maximumCharacters: budget)
      precondition((bounded.text?.count ?? 0) <= budget)
    }
    var ten = first
    for index in 1...9 {
      let file = AIAttachment(id: UUID(), name: "File \(index)", url: root.appendingPathComponent("\(index).txt"))
      ten.append(file)
      await SourceExtractionCache.shared.set(file.url, blocks: (0..<100).map { .init(text: "Evidence \($0) " + String(repeating: "x", count: 100)) })
    }
    await SourceExtractionCache.shared.set(first.url, blocks: (0..<100).map { .init(text: "Evidence \($0)") })
    let multiple = await AIAttachmentText.prepare(ten, question: "Evidence")
    precondition(multiple.failure == nil && (multiple.text?.count ?? 0) <= 60_000)
    precondition(multiple.attachmentCitations.count == 64)
    precondition(Set(multiple.attachmentCitations.map { $0.file.id }).count == 10)
    let temporary = AIAttachment(id: UUID(), name: "Temporary office file",
      url: root.deletingLastPathComponent().appendingPathComponent("temporary.docx"))
    await SourceExtractionCache.shared.set(temporary.url, blocks: [.init(text: "Accessible original evidence", page: 4)])
    let original = await AIAttachmentText.prepare(temporary, maximumCharacters: 300)
    precondition(original.failure == nil && original.text?.contains("Accessible original evidence") == true)
    precondition(original.text?.contains("ページ4") == true && original.attachmentCitations.isEmpty)
    precondition(original.text?.contains("【添付") == false && (original.text?.count ?? 0) <= 300)
    precondition(PreparedAIAttachment(id: first.id, name: first.name, url: first.url).attachmentCitations.isEmpty)
    print("AttachmentCitationChecks: PASS. Production preparation/selection/reference code with fixture extraction; late-page and timestamp evidence, Unicode-safe byte limits, complete-excerpt filtering at every character cut, ten-file budgets, 64-citation limit and invalid persisted metadata rejection. No model/device/network claim.")
  }
}

// Parsing is isolated here so this check exercises preparation without a speech engine or network.
struct FixtureExtraction: Sendable {
  var blocks: [ProjectSourceText]
  var notice: String?
}

actor SourceExtractionCache {
  static let shared = SourceExtractionCache()
  private var results: [URL: FixtureExtraction] = [:]
  func set(_ url: URL, blocks: [ProjectSourceText]) { results[url] = .init(blocks: blocks) }
  func extract(_ url: URL, vocabulary: [String]) throws -> FixtureExtraction {
    guard let value = results[url] else { throw FixtureFailure.missing }
    return value
  }
}

enum ProjectSourceExtraction {
  static func read(_ url: URL, includesThumbnail: Bool) throws -> FixtureExtraction { throw FixtureFailure.missing }
}

enum ProjectSourceFiles {
  enum Failure: Error { case tooLarge }
}

enum OfficeArchiveReader {
  enum Failure: LocalizedError {
    case unsupported
    var errorDescription: String? { "Unsupported fixture" }
  }
}

private enum FixtureFailure: Error { case missing }
