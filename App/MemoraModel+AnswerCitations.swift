import Foundation

extension MemoraModel {
  func answerCitationTargets(for message: AIChatMessage) -> Set<ArtifactSourceTarget> {
    let provenance = artifactProvenance(for: message)
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, provenance.workspaceID == currentTeamID else { return [] }
    let sent = AnswerSourceCitation.targets(provenance: provenance, meetingIDs: message.sources.map(\.meetingID))
      // Provenance project files carry the fingerprint read at generation time;
      // a source that changed since then is no longer evidence for this answer.
      .filter { target in
        guard case .projectFile(let id) = target else { return true }
        guard let source = source(id: id) else { return false }
        let reference = provenance.projectSources.first { $0.id == id }
        return ProjectCitationTargets.projectFileIsCurrent(reference,
          projectID: source.projectID, fingerprint: AIRecordFingerprint.make(source))
      }
    // Retrieved project sources were sent to the model; link only those whose
    // source still exists in a live project and still holds the same evidence.
    let projectFiles = ProjectCitationTargets.live(message.sourceCitations) { [self] id in
      guard let source = source(id: id) else { return nil }
      return .init(isReadable: source.canProvideText,
        reference: source.extractedTextReference, fingerprint: source.contentFingerprint)
    }.filter { target in
      guard case .projectFile(let id) = target else { return true }
      return source(id: id)?.projectID.map { space(id: $0) != nil } ?? true
    }
    return sent.union(projectFiles)
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
    if let target = AnswerSourceCitation.target(for: url) {
      guard allowed.contains(target) else { return nil }
      switch target {
      case .projectFile(let id):
        guard let source = source(id: id), source.canProvideText else { return nil }
        // A stamped document must still match the text reference it was built
        // from. Documents saved before stamps existed stay open as current
        // links; their original evidence cannot be re-verified.
        let reference = document.provenance?.projectSources.first { $0.id == id }
        guard ProjectCitationTargets.projectFileIsCurrent(reference,
          projectID: source.projectID, fingerprint: AIRecordFingerprint.make(source)) else { return nil }
      case .record(let record):
        if let reference = document.provenance?.records.first(where: { $0.target == record }),
           recordReference(for: record) != reference { return nil }
      }
      return target
    }
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
