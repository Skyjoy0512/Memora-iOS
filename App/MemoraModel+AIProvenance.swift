import Foundation

extension MemoraModel {
  var cloudMemoryFingerprint: String {
    AIRecordFingerprint.make(isAIMemoryEnabled ? aiMemories : []) ?? ""
  }

  func recordReference(for target: RecordPrivacyTarget) -> AIRecordReference? {
    let fingerprint: String?
    switch target {
    case .meeting(let id): fingerprint = meeting(id: id).flatMap(AIRecordFingerprint.make)
    case .journal(let id): fingerprint = lifeLogEntries.first { $0.id == id }.flatMap(AIRecordFingerprint.make)
    case .task(let id): fingerprint = tasks.first { $0.id == id }.flatMap(AIRecordFingerprint.make)
    case .person(let id): fingerprint = person(id: id).map(PersonAIContext.init).flatMap(AIRecordFingerprint.make)
    }
    return fingerprint.map { AIRecordReference(target: target, fingerprint: $0) }
  }

  func canReuseCloudConversation(_ provenance: AIConversationProvenance?) -> Bool {
    guard !isRestoring, !isStoreProtected, let provenance else { return false }
    return provenance.allowsReuse(workspaceID: currentTeamID, memoryFingerprint: cloudMemoryFingerprint,
      resolve: recordReference, allows: { allowsRecordAccess($0, purpose: .cloudAI) })
  }

  func cloudConversationContext(for questionText: String = "") -> (text: String, references: [AIRecordReference]) {
    var question: String?
    var exchanges: [(String, [AIRecordReference])] = []
    for message in aiMessages {
      if message.role == .user { question = message.text; continue }
      guard !message.isThinking, let question,
            canReuseCloudConversation(message.cloudProvenance), let provenance = message.cloudProvenance else { continue }
      exchanges.append(("利用者: \(question)\n回答: \(message.text)", provenance.references))
    }
    let episode = relatedEpisodeContext(for: questionText, budget: 1_500, cloud: true)
    var recent = Array(exchanges.suffix(3))
    if !episode.text.isEmpty { recent.insert((episode.text, episode.references), at: 0) }
    let references = Array(Set(recent.flatMap { $0.1 }))
    guard references.count <= 256 else { return ("", []) }
    return (Self.trailingHistory(recent.map { $0.0 }.joined(separator: "\n"), budget: 3_000), references)
  }

  func newCloudProvenance(references: [AIRecordReference]) -> AIConversationProvenance {
    AIConversationProvenance(references: references, workspaceID: currentTeamID,
      memoryFingerprint: cloudMemoryFingerprint)
  }

  var cloudAuthorizedTargets: Set<RecordPrivacyTarget> {
    guard !isRestoring, !isStoreProtected else { return [] }
    return Set(meetings.filter { RecordAccessPolicy.allows($0.effectivePrivacy, purpose: .cloudAI) }.map { .meeting($0.id) }
      + lifeLogEntries.filter { allowsJournalAccess($0, purpose: .cloudAI) }.map { .journal($0.id) }
      + tasks.filter { allowsTaskAccess($0, purpose: .cloudAI) }.map { .task($0.id) }
      + people.filter { allowsPersonAccess($0.id, purpose: .cloudAI) }.map { .person($0.id) })
  }

  func recordCloudReads(_ targets: [RecordPrivacyTarget], messageID: UUID) {
    guard agentMessage(messageID)?.cloudProvenance != nil else { return }
    let unique = Set(targets)
    updateAgentMessage(messageID) { message in
      message.cloudAuthorizationTargets?.formUnion(unique)
    }
    guard unique.count <= 256 else { markCloudProvenanceIncomplete(messageID); return }
    let references = unique.compactMap(recordReference)
    updateAgentMessage(messageID) { message in
      guard var provenance = message.cloudProvenance else { return }
      if references.count != unique.count { provenance.isComplete = false }
      let all = Set(provenance.references).union(references)
      if all.count <= 256 { provenance.references = Array(all) }
      else { provenance.isComplete = false }
      message.cloudProvenance = provenance
    }
  }

  func markCloudProvenanceIncomplete(_ messageID: UUID) {
    updateAgentMessage(messageID) { $0.cloudProvenance?.isComplete = false }
  }

  func isCloudSessionAuthorized(_ messageID: UUID) -> Bool {
    guard !isRestoring, !isStoreProtected, let message = agentMessage(messageID),
          let provenance = message.cloudProvenance, let targets = message.cloudAuthorizationTargets else { return false }
    if let policy = agentPluginPolicies[messageID] {
      guard personPolicyIsCurrent(policy) else { return false }
    }
    guard message.projectSourceReferences.allSatisfy({ reference in
      guard let source = source(id: reference.id), source.projectID == reference.projectID else { return false }
      return canReadAgentSource(source, compact: false, policy: agentPluginPolicies[messageID]) && AIRecordFingerprint.make(source) == reference.fingerprint
    }) else { return false }
    return provenance.workspaceID == currentTeamID && provenance.memoryFingerprint == cloudMemoryFingerprint
      && cloudAuthorizedTargets.isSuperset(of: targets)
      && provenance.references.allSatisfy { recordReference(for: $0.target) == $0 && allowsRecordAccess($0.target, purpose: .cloudAI) }
  }
}
