import Foundation

extension MemoraModel {
  /// Editing extraction creates a version. It never rewrites the source,
  /// generated prose, previous evidence or the person's task state.
  @discardableResult
  func saveSummaryFact(meetingID: UUID, versionID: UUID, original: SummaryKnowledge.Fact?,
                       category: SummaryKnowledge.Category, content: String,
                       status: SummaryKnowledge.Status) -> Bool {
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty, content.count <= 4_000, !processing.isActive(meetingID),
          let meeting = meeting(id: meetingID), meeting.activeSummaryVersionID == versionID,
          let version = meeting.summaryVersions.first(where: { $0.id == versionID && $0.sourceRecordID == meetingID }),
          var knowledge = version.knowledge else { return false }
    if let original {
      guard let index = knowledge.facts.firstIndex(where: { $0 == original }) else { return false }
      knowledge.facts[index].content = content
      knowledge.facts[index].category = category
      knowledge.facts[index].status = status
      knowledge.facts[index].origin = .user
      // A changed assertion cannot inherit a generated quote as proof.
      knowledge.facts[index].sourceReferences = []
    } else {
      guard knowledge.facts.count < 256 else { return false }
      knowledge.facts.append(.init(id: UUID().uuidString, category: category, content: content,
        status: status, sourceReferences: [], origin: .user))
    }
    var replacement = version
    replacement.id = UUID()
    replacement.generatedAt = .now
    replacement.modelInfo = "本人による抽出情報の編集"
    replacement.knowledge = knowledge
    replacement.reconciledUserEdits = true
    return updateMeeting(meetingID) {
      $0.summaryVersions.append(replacement)
      $0.activeSummaryVersionID = replacement.id
    }
  }
}
