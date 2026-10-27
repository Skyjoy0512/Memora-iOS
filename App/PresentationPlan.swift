import Foundation

/// Planning metadata is evidence to review, never a permission to read its sources.
struct PresentationPlan: Codable, Hashable, Sendable {
  var purpose = ""
  var audience = ""
  var decision = ""
  var assumptions: [String] = []
  var storyline: [Point] = []

  struct Point: Codable, Hashable, Identifiable, Sendable {
    var slideID: UUID
    var claim: String
    var evidence: [String] = []
    var unconfirmed: [String] = []
    var id: UUID { slideID }
  }

  func isValid(for slides: [DocumentSlide]) -> Bool {
    let ids = Set(slides.map(\.id))
    return storyline.count <= 65 && Set(storyline.map(\.slideID)).count == storyline.count
      && storyline.allSatisfy { ids.contains($0.slideID) && !$0.claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && $0.claim.utf8.count <= 1_000 && bounded($0.evidence) && bounded($0.unconfirmed) }
      && [purpose, audience, decision].allSatisfy { $0.utf8.count <= 2_000 }
      && bounded(assumptions)
  }

  func reconciled(with slides: [DocumentSlide]) -> Self {
    var result = self
    let byID = Dictionary(storyline.map { ($0.slideID, $0) }, uniquingKeysWith: { first, _ in first })
    result.storyline = slides.compactMap { byID[$0.id] }
    return result
  }

  func reviewNotes(for slides: [DocumentSlide]) -> [String] {
    var notes: [String] = []
    if purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.append("資料の目的が未確認です。") }
    if audience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.append("対象読者が未確認です。") }
    if decision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.append("判断してほしいことが未確認です。") }
    let planned = Set(storyline.map(\.slideID))
    if slides.contains(where: { !planned.contains($0.id) }) { notes.append("構成の主張が未設定のスライドがあります。") }
    if !assumptions.isEmpty || storyline.contains(where: { !$0.unconfirmed.isEmpty }) { notes.append("未確認事項があります。原資料と照合してください。") }
    return notes
  }

  private func bounded(_ values: [String]) -> Bool {
    values.count <= 20 && values.allSatisfy { $0.utf8.count <= 2_000 }
  }
}
