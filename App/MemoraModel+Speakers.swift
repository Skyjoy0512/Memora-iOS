import Foundation

extension MemoraModel {
  func analyzeSpeakers(_ id: UUID) async {
    guard currentTeamID == nil, !isEnrollingSpeaker, !speakerAnalysisIDs.contains(id), !processing.isActive(id), !isRestoring, isStoreWritable(),
          let record = meeting(id: id), let audioURL = record.audioURL, !record.transcript.isEmpty else { return }
    guard record.transcript.contains(where: { $0.endTime != nil }) else {
      speakerAnalysisMessages[id] = "この文字起こしには発言の終了時刻がありません。自動の話者割り当ては行いません。話者名は手動で編集できます。"
      return
    }
    let revision = ProcessingService.inputRevision(record.transcript)
    let generation = aiWorkspaceGeneration
    let enrollmentRevision = speakerEnrollmentRevision
    speakerAnalysisIDs.insert(id)
    speakerAnalysisMessages[id] = "端末内で話者を解析しています…"
    defer { speakerAnalysisIDs.remove(id) }
    do {
      let service: any SpeakerDiarizationService = FluidSpeakerDiarizationService.shared
      let result = try await service.analyze(audioURL)
      try Task.checkCancellation()
      guard !isRestoring, currentTeamID == nil, aiWorkspaceGeneration == generation, isStoreWritable(),
            let current = meeting(id: id), current.audioURL == audioURL, current.privacy == record.privacy,
            ProcessingService.inputRevision(current.transcript) == revision else {
        speakerAnalysisMessages[id] = "記録が変わったため解析結果は反映しませんでした。"
        return
      }
      let aligned = SpeakerTranscriptAligner.align(current.transcript, intervals: result.intervals, minimumDuration: 1)
      guard updateMeeting(id, change: { $0.transcript = aligned }) else {
        speakerAnalysisMessages[id] = "解析しましたが、話者情報の保存を完了できませんでした。原音声・原文は保持しています。保存状態を確認して再試行してください。"
        return
      }
      let matched = aligned.filter { $0.identificationStatus == .anonymous }.count
      var message = "\(matched)件の発言に匿名の話者を割り当てました。手動で確認・修正できます。"
      var storedCandidate = false
      if currentTeamID == nil, isStoreWritable() {
        var candidate: SpeakerTaskOwnershipEvidence?
        if speakerEnrollmentRevision == enrollmentRevision,
           let profile = speakerProfile, profile.isEnabled, profile.isValid {
          do {
            let limits = Self.speakerTaskMatchLimits
            if let winner = try SpeakerIdentificationService.selfMatch(
              profile: profile, result: result,
              minimumSimilarity: limits.similarity, minimumLead: limits.lead,
              minimumEligibleSpeech: limits.speech),
               aligned.contains(where: {
                 $0.identificationStatus == .anonymous && $0.speakerID == winner.speakerID
               }),
               let fingerprint = SummaryEvidence.fingerprint(aligned) {
              candidate = SpeakerTaskOwnershipEvidence(
                recordID: id, speakerID: winner.speakerID, profileID: profile.id,
                profileUpdatedAt: profile.updatedAt, transcriptFingerprint: fingerprint,
                similarity: winner.similarity)
            }
          } catch SpeakerProcessingFailure.modelMismatch {
            message += " 声のモデルが変わったため再登録が必要です。"
          } catch { }
        }
        if let entries = replacingSpeakerTaskEvidence(recordID: id, candidate: candidate),
           persistNow(entries, forKey: SpeakerTaskOwnershipEvidence.storageKey) {
          storedCandidate = candidate != nil
        }
      }
      if storedCandidate { message += " 登録した声と一致する話者の候補があります。" }
      speakerAnalysisMessages[id] = message
    } catch is CancellationError {
      speakerAnalysisMessages[id] = "解析を中断しました。原音声・文字起こしは保持しています。"
    } catch {
      speakerAnalysisMessages[id] = "話者解析を完了できませんでした。\(error.localizedDescription)"
    }
  }

  /// Whether an action the summary credited to the person was said by the
  /// cluster the registered voice matched. Nil leaves the name-based rule in
  /// charge, which is also what happens before a voice analysis has run.
  func speakerActionOwnership(owner: String?, title: String, in record: Meeting) -> ActionTaskOwner.Ownership? {
    guard let evidence = currentSpeakerTaskEvidence(for: record) else { return nil }
    return ActionTaskOwner.ownership(
      owner: owner, names: [profile.name, account?.displayName ?? ""],
      actionTitle: title, transcript: record.transcript, ownSpeakerID: evidence.speakerID)
  }

  func currentSpeakerTaskEvidence(for record: Meeting) -> SpeakerTaskOwnershipEvidence? {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected,
          let stored = meeting(id: record.id), stored == record,
          let profile = speakerProfile, profile.isEnabled, profile.isValid,
          let fingerprint = SummaryEvidence.fingerprint(record.transcript),
          let entries = speakerTaskEvidenceEntries() else { return nil }
    let limits = Self.speakerTaskMatchLimits
    return entries.first { evidence in
      evidence.matches(recordID: record.id, profile: profile,
                       transcriptFingerprint: fingerprint,
                       minimumSimilarity: limits.similarity)
        && record.transcript.contains {
          $0.identificationStatus == .anonymous && $0.speakerID == evidence.speakerID
        }
    }
  }

  private func replacingSpeakerTaskEvidence(recordID: UUID,
      candidate: SpeakerTaskOwnershipEvidence?) -> [SpeakerTaskOwnershipEvidence]? {
    guard let entries = speakerTaskEvidenceEntries() else { return nil }
    let retained = entries.filter { $0.recordID != recordID }
    let updated = candidate.map { [$0] + retained } ?? retained
    return Array(updated.prefix(SpeakerTaskOwnershipEvidence.maximumEntries))
  }

  private func speakerTaskEvidenceEntries() -> [SpeakerTaskOwnershipEvidence]? {
    switch RecordStore.loadLatestData(SpeakerTaskOwnershipEvidence.storageKey) {
    case .absent:
      return []
    case .failed:
      return nil
    case .data(let data):
      // Unreadable bytes must fail closed, like a failed read: overwriting them
      // with a new candidate would silently discard every prior entry.
      return try? JSONDecoder().decode([SpeakerTaskOwnershipEvidence].self, from: data)
    }
  }
}
