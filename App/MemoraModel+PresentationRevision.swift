import Foundation

extension MemoraModel {
  /// A local, non-restored grant tied to this exact document, workspace and model.
  func presentationRevisionAuthorization(for original: MemoraDocument, engine: AIEngine,
                                         llm: LLMSelection) -> @MainActor () -> Bool {
    let generation = aiWorkspaceGeneration
    let configurationRevision = summaryConfigurationIdentity
    let cloud = AIEngineService.effectiveEngine(engine) == .cloud
    let purpose: RecordAccessPolicy.Purpose = cloud ? .cloudAI : .onDeviceAI
    let provenance = original.provenance
    let privacyDates = provenance?.records.map { privacy(for: $0.target)?.updatedAt }
    return { [weak self] in
      guard let self, !Task.isCancelled, !self.isRestoring, !self.isStoreProtected,
            self.currentTeamID == nil, self.aiWorkspaceGeneration == generation,
            self.summaryConfigurationIdentity == configurationRevision,
            self.askAIConfiguration.engine == engine, self.askAIConfiguration.llm == llm,
            self.document(id: original.id) == original, original.companyTemplateID == nil,
            provenance?.workspaceID == nil, provenance?.isValid ?? true else { return false }
      // Incomplete legacy attribution cannot prove that hidden material is cloud-permitted.
      if cloud && (provenance?.isComplete != true || llm.isMemoraIntelligence) { return false }
      if let provenance {
        guard provenance.records.map({ self.privacy(for: $0.target)?.updatedAt }) == privacyDates,
              provenance.records.allSatisfy({ self.recordReference(for: $0.target) == $0
                && self.allowsRecordAccess($0.target, purpose: purpose) }),
              provenance.projectSources.allSatisfy({ reference in
                guard let source = self.source(id: reference.id), source.projectID == reference.projectID else { return false }
                return self.canReadAgentSource(source, compact: !cloud, policy: nil)
                  && AIRecordFingerprint.make(source) == reference.fingerprint
              }) else { return false }
      }
      let records = Set((provenance?.records ?? []).compactMap { reference -> UUID? in
        if case .meeting(let id) = reference.target { return id }; return nil
      })
      let files = Set((provenance?.projectSources ?? []).map(\.id))
      if cloud && (!Set(original.sourceRecordIDs ?? []).isSubset(of: records)
        || !Set(original.sourceProjectFileIDs ?? []).isSubset(of: files)) { return false }
      return true
    }
  }
}
