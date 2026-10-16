import Foundation

extension MemoraModel {
  func artifactProvenance(for message: AIChatMessage) -> ArtifactProvenance {
    var result = message.artifactProvenance ?? ArtifactProvenance(
      workspaceID: currentTeamID, sourceMessageID: message.id, capturedAt: message.createdAt)
    if let cloud = message.cloudProvenance {
      result.workspaceID = cloud.workspaceID
      result.records = cloud.references
      result.isComplete = cloud.isComplete
    }
    // These are metadata copies, not restored AgentSourceReference grants.
    if !message.projectSourceReferences.isEmpty {
      let existing = Set(result.projectSources.map(\.id))
      result.projectSources += message.projectSourceReferences.filter { !existing.contains($0.id) }.prefix(max(0, 32 - result.projectSources.count)).map {
        ArtifactProjectSourceReference(id: $0.id, projectID: $0.projectID, fingerprint: $0.fingerprint)
      }
      result.isComplete = false
    }
    if message.sources.contains(where: { source in !result.records.contains { $0.target == .meeting(source.meetingID) } }) {
      result.isComplete = false
    }
    return result
  }

  func artifactCreationIsCurrent(messageID: UUID, workspaceID: String?, provenance: ArtifactProvenance) -> Bool {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == workspaceID,
          workspaceID == nil, provenance.workspaceID == workspaceID, provenance.isValid,
          let message = agentMessage(messageID) else { return false }
    if let policy = agentPluginPolicies[messageID], !personPolicyIsCurrent(policy) { return false }
    if message.cloudProvenance != nil, !isCloudSessionAuthorized(messageID) { return false }
    return provenance.records.allSatisfy { recordReference(for: $0.target) == $0 && allowsRecordAccess($0.target, purpose: .onDeviceAI) }
      && provenance.projectSources.allSatisfy {
        guard let source = source(id: $0.id), source.projectID == $0.projectID else { return false }
        return canReadAgentSource(source, compact: true, policy: agentPluginPolicies[messageID])
          && AIRecordFingerprint.make(source) == $0.fingerprint
      }
  }

  func canOpenArtifactSource(_ target: ArtifactSourceTarget, workspaceID: String?) -> Bool {
    guard currentTeamID == nil, workspaceID == currentTeamID, !isRestoring, !isStoreProtected else { return false }
    switch target {
    case .record(let record):
      // Local navigation is independent of cloud permission, including private journal entries.
      switch record {
      case .meeting(let id): return meeting(id: id) != nil
      case .journal(let id): return lifeLogEntries.contains { $0.id == id }
      case .task(let id): return tasks.contains { $0.id == id }
      case .person(let id): return person(id: id) != nil
      }
    case .projectFile(let id):
      guard let source = source(id: id) else { return false }
      return source.projectID.map { space(id: $0) != nil } ?? true
    }
  }

  func artifactSourceRows(provenance: ArtifactProvenance?, meetingIDs: [UUID] = [],
                          projectFileIDs: [UUID] = [], legacyWorkspaceID: String? = nil) -> [ArtifactSourceRow] {
    let workspaceID = provenance?.workspaceID ?? legacyWorkspaceID
    guard currentTeamID == nil, workspaceID == currentTeamID, !isRestoring, !isStoreProtected,
          provenance?.isValid ?? true else { return [] }
    var targets = (provenance?.records ?? []).map { ArtifactSourceTarget.record($0.target) }
      + (provenance?.projectSources ?? []).map { .projectFile($0.id) }
    targets += meetingIDs.prefix(256).map { .record(.meeting($0)) }
      + projectFileIDs.prefix(32).map { .projectFile($0) }
    var seen = Set<ArtifactSourceTarget>()
    return targets.filter { seen.insert($0).inserted }.prefix(288).map { target in
      var row = ArtifactSourceRow(target: target, title: target.label, allowsCloudAI: false,
        canOpen: canOpenArtifactSource(target, workspaceID: workspaceID))
      guard row.canOpen else { return row }
      switch target {
      case .record(let record):
        switch record {
        case .meeting(let id): row.title = meeting(id: id)?.displayTitle ?? target.label
        case .journal(let id): row.title = lifeLogEntries.first { $0.id == id }?.title ?? target.label
        case .task(let id): row.title = tasks.first { $0.id == id }?.title ?? target.label
        case .person(let id): row.title = person(id: id)?.name ?? target.label
        }
        row.hasChanged = provenance?.records.first { $0.target == record }.map { recordReference(for: record) != $0 }
        row.allowsCloudAI = allowsRecordAccess(record, purpose: .cloudAI)
      case .projectFile(let id):
        if let source = source(id: id) {
          row.title = source.title
          row.hasChanged = provenance?.projectSources.first { $0.id == id }.map {
            source.projectID != $0.projectID || AIRecordFingerprint.make(source) != $0.fingerprint
          }
          row.allowsCloudAI = canReadAgentSource(source, compact: false, policy: nil)
        }
      }
      return row
    }
  }
}
