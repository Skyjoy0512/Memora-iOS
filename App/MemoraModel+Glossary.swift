import Foundation

// The words a business uses — company, product and people's names — so
// transcription hears them and summaries spell them the same way.
extension MemoraModel {
  /// The most terms handed to an engine; recognisers weigh a short list best.
  static let vocabularyLimit = 100

  @discardableResult
  func addGlossaryTerm(_ term: String) -> Bool {
    let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !glossaryTerms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
      return false
    }
    glossaryTerms.append(trimmed)
    return true
  }

  func removeGlossaryTerm(_ term: String) {
    glossaryTerms.removeAll { $0 == term }
  }

  /// Local recognition can use the address-book vocabulary without sending it.
  var transcriptionVocabulary: [String] {
    Self.normalizedVocabulary(glossaryTerms + people.map(\.name) + spaces.map(\.name))
  }

  /// Explicitly registered terms have their own consent; person/project metadata does not.
  func processingVocabulary(external: Bool) -> [String] {
    external ? Self.normalizedVocabulary(glossaryTerms) : transcriptionVocabulary
  }

  private static func normalizedVocabulary(_ candidates: [String]) -> [String] {
    var seen: Set<String> = []
    return candidates
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
      .prefix(Self.vocabularyLimit)
      .map { $0 }
  }
}
