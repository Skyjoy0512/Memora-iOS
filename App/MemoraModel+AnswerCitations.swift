import Foundation

extension MemoraModel {
  func answerCitationTargets(for message: AIChatMessage) -> Set<ArtifactSourceTarget> {
    let provenance = artifactProvenance(for: message)
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, provenance.workspaceID == currentTeamID else { return [] }
    return AnswerSourceCitation.targets(provenance: provenance, meetingIDs: message.sources.map(\.meetingID))
  }

  func answerCitationTarget(for url: URL, message: AIChatMessage) -> ArtifactSourceTarget? {
    let target = AnswerSourceCitation.target(for: url)
      ?? AnswerCitations.source(for: url, in: message.sources).map { .record(.meeting($0.meetingID)) }
    guard let target, answerCitationTargets(for: message).contains(target) else { return nil }
    return target
  }

  func documentCitationTarget(for url: URL, document: MemoraDocument) -> ArtifactSourceTarget? {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected,
          document.provenance?.workspaceID == currentTeamID, document.provenance?.isValid ?? true else { return nil }
    let allowed = AnswerSourceCitation.targets(provenance: document.provenance,
      meetingIDs: document.sourceRecordIDs ?? [], projectFileIDs: document.sourceProjectFileIDs ?? [])
    if let target = AnswerSourceCitation.target(for: url) { return allowed.contains(target) ? target : nil }
    // Earlier saved answers have meeting URLs but no separate source metadata.
    guard let id = UUID(uuidString: url.lastPathComponent),
          url.absoluteString.lowercased() == MeetingLink.url(for: id)?.absoluteString.lowercased() else { return nil }
    let target = ArtifactSourceTarget.record(.meeting(id))
    return document.provenance == nil || allowed.contains(target) ? target : nil
  }

  func openExternalSourceCitation(_ url: URL) {
    pendingSourceCitation = nil
    guard let target = AnswerSourceCitation.target(for: url), canOpenArtifactSource(target, workspaceID: nil) else {
      missingRecordNotice = MissingRecordNotice(message: "個人ワークスペースで元の情報を確認してください。削除済み、復元中、またはこの端末に存在しない情報は開けません。", offersTrash: false)
      return
    }
    // An explicit link opens local information only. It never creates an AI grant.
    missingRecordNotice = nil
    pendingSourceCitation = target
  }
}
