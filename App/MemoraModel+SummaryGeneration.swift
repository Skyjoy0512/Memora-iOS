import Foundation

extension MemoraModel {
  /// Rewrites the summary from the real transcript with the chosen template,
  /// then files its decisions, open questions and key points on the record and
  /// its actions in the tasks tab. Nothing is invented: when no engine can
  /// answer, the record says so and keeps whatever the person had.
  ///
  /// `configuration` is the AI chosen in the summary sheet; without one, the
  /// settings engine is used.
  @discardableResult
  func generateSummary(
    _ id: UUID,
    choice: SummaryTemplateChoice,
    configuration: (engine: AIEngine, llm: LLMSelection)? = nil,
    automaticallySelect: Bool = false,
    useCaseID: String? = nil,
    preferences: SummaryPreferences? = nil,
    submission: SummarySubmissionIntent? = nil,
    pendingJob: PendingSummaryJob? = nil
  ) -> Bool {
    guard let meeting = meeting(id: id), !meeting.transcript.isEmpty,
          currentTeamID == nil, !speakerAnalysisIDs.contains(id), !processing.isActive(id),
          !isRestoring, isStoreWritable() else { return false }
    guard meeting.transcript.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      announce("要約できる文字起こしがありません。原文を確認してください。")
      return false
    }
    let workspaceGeneration = aiWorkspaceGeneration
    let configurationIdentity = summaryConfigurationIdentity
    let selectedEngine = configuration?.engine ?? settingsAIConfiguration.engine
    let effectiveEngine = AIEngineService.effectiveEngine(selectedEngine)
    let usesCloud = effectiveEngine == .cloud || effectiveEngine == .memora
    let llm = configuration?.llm ?? settingsAIConfiguration.llm
    let explicitSubmission = pendingJob == nil && submission?.matches(meetingID: id,
      fingerprint: SummaryJobFingerprint.make(meeting), workspace: workspaceGeneration,
      engine: selectedEngine, llm: llm) == true
    if submission != nil && !explicitSubmission { return false }
    if effectiveEngine == .cloud || effectiveEngine == .memora {
      guard explicitSubmission ? RecordAccessPolicy.allowsSummarySubmission(meeting.effectivePrivacy)
        : RecordAccessPolicy.allows(meeting.effectivePrivacy, purpose: .cloudAI) else {
        announce(RecordAccessPolicy.refusal)
        return false
      }
    }

    if let submission, !submission.consume() { return false }
    let startedAt = Date()
    let input = MeetingSummaryInput(
      title: meeting.displayTitle,
      date: meeting.createdAt,
      duration: meeting.duration,
      participantNames: usesCloud ? [] : (meeting.participantIDs ?? []).compactMap { person(id: $0)?.name },
      transcript: meeting.transcript,
      template: choice,
      glossary: processingVocabulary(external: usesCloud),
      preferences: preferences ?? summaryPreferences,
      automaticCandidates: automaticallySelect ? automaticSummaryCandidates(for: meeting, fallback: choice) : []
    )
    let engine = configuration?.engine ?? settingsAIConfiguration.engine

    let job = pendingJob ?? PendingSummaryJob(
        id: submission?.jobID ?? UUID(),
        meetingID: id,
        choice: choice,
        engineRawValue: engine.rawValue,
        llm: llm,
        automaticallySelect: automaticallySelect,
        useCaseID: useCaseID,
        preferences: input.preferences,
        cloudDisclosureConfirmed: usesCloud && explicitSubmission,
        usesCloud: usesCloud,
        inputFingerprint: SummaryJobFingerprint.make(meeting)
      )
    guard job.meetingID == id, job.inputFingerprint != nil,
          job.engine == engine, job.llm == llm, job.usesCloud == usesCloud,
          job.inputFingerprint == SummaryJobFingerprint.make(meeting) else { return false }
    if pendingJob != nil && (job.cloudDisclosureConfirmed || job.requiresUserRetry == true || job.attemptStartedAt != nil) {
      return false
    }
    if pendingJob == nil {
      guard enqueueBackgroundSummary(job) else { return false }
    } else {
      guard pendingSummaryJobs.contains(where: { $0.id == job.id }) else { return false }
    }
    var startedJobs = pendingSummaryJobs
    guard let jobIndex = startedJobs.firstIndex(where: { $0.id == job.id }) else { return false }
    startedJobs[jobIndex].attemptStartedAt = startedAt
    startedJobs[jobIndex].requiresUserRetry = true
    guard persistNow(startedJobs, forKey: StorageKey.pendingSummaryJobs) else { return false }
    pendingSummaryJobs = startedJobs
    let diagnostics = SummaryDiagnostics(jobID: job.id, engine: effectiveEngine.rawValue,
      provider: usesCloud ? llm.provider.rawValue : "onDevice", model: usesCloud ? llm.modelID : "system",
      characters: meeting.transcript.reduce(0) { $0 + $1.text.count }, segments: meeting.transcript.count)
    diagnostics.record(.processingMode, code: input.preferences.processingMode.diagnosticCode)
    updateMeeting(id) { $0.status = .organizing(choice.processingLabel) }
    backgroundSummaryNotice = nil
    // Automatic OS wakeups use their delivered processing window; only a
    // person starting work in the foreground requests continued processing.
    if summaryBackgroundScheduler.isForeground {
      summaryBackgroundScheduler.begin(jobID: job.id, requestsContinuedProcessing: pendingJob == nil) { [weak self] in
        diagnostics.record(.backgroundExpiration)
        self?.pauseBackgroundSummary(job, requiresUserRetry: true)
      } onFailure: { [weak self] message in
        self?.backgroundSummaryNotice = message
      }
    }

    processing.run(id: id) { [weak self] in
      let outcome = await SummaryDiagnostics.$current.withValue(diagnostics) {
        await MeetingSummarizer.summarize(input, engine: engine, llm: llm, authorize: { [weak self] in
          guard let self, !Task.isCancelled, self.aiWorkspaceGeneration == workspaceGeneration,
                self.currentTeamID == nil, !self.isRestoring, !self.isStoreProtected,
                self.summaryConfigurationIdentity == configurationIdentity,
                self.pendingSummaryJobs.contains(where: { $0.id == job.id }),
                let current = self.meeting(id: id), SummaryJobFingerprint.make(current) == job.inputFingerprint,
                (!usesCloud || RecordAccessPolicy.allows(current.effectivePrivacy, purpose: .cloudAI,
                  explicitCloudConsent: explicitSubmission)) else {
            diagnostics.record(.contextChanged)
            self?.pauseBackgroundSummary(job, requiresUserRetry: true)
            return false
          }
          return true
        }) { step in
          guard let self, !Task.isCancelled else { return }
          guard self.aiWorkspaceGeneration == workspaceGeneration, self.currentTeamID == nil,
                !self.isRestoring, !self.isStoreProtected,
                self.summaryConfigurationIdentity == configurationIdentity,
                let current = self.meeting(id: id), current.privacy == meeting.privacy,
                current.spaceID == meeting.spaceID,
                (!usesCloud || RecordAccessPolicy.allows(current.effectivePrivacy, purpose: .cloudAI,
                  explicitCloudConsent: explicitSubmission)) else {
            self.pauseBackgroundSummary(job, requiresUserRetry: true)
            diagnostics.record(.contextChanged)
            return
          }
          self.summaryBackgroundScheduler.report(jobID: job.id, step: step)
          self.updateMeetingTransiently(id) { meeting in
            if case .organizing = meeting.status {
              meeting.status = .organizing("\(choice.processingLabel)：\(step)")
            }
          }
        }
      }
      if Task.isCancelled { diagnostics.record(.cancelled) }
      return outcome
    } apply: { [weak self] result in
      guard let self, !Task.isCancelled,
            self.pendingSummaryJobs.contains(where: { $0.id == job.id }) else { return }
      var delivered = false
      defer {
        self.activeSummaryRuns.removeValue(forKey: job.id)
        self.summaryBackgroundScheduler.finish(jobID: job.id, success: delivered)
      }
      self.performance.record(
        "処理（要約）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000
      )

      // A transcript/summary edit or a changed disclosure wins over the older
      // result. Hash only at the request boundaries, never on streaming ticks.
      guard let current = self.meeting(id: id) else { return }
      guard !self.isRestoring, self.isStoreWritable(), self.currentTeamID == nil,
            self.aiWorkspaceGeneration == workspaceGeneration,
            self.summaryConfigurationIdentity == configurationIdentity else {
        self.pauseBackgroundSummary(job, requiresUserRetry: true)
        return
      }
      guard SummaryJobFingerprint.make(current) == job.inputFingerprint,
            (!usesCloud || RecordAccessPolicy.allows(current.effectivePrivacy, purpose: .cloudAI,
              explicitCloudConsent: explicitSubmission)) else {
        diagnostics.record(.contextChanged)
        self.pauseBackgroundSummary(job, requiresUserRetry: true)
        return
      }
      switch result {
      case .success(let summary):
        guard let index = self.meetings.firstIndex(where: { $0.id == id }) else { return }
        var candidateMeetings = self.meetings
        do {
          var meeting = candidateMeetings[index]
          if !meeting.summary.isEmpty, !meeting.summaryVersions.contains(where: { $0.markdown == meeting.summary }) {
            meeting.summaryVersions.append(.snapshot(record: meeting, templateID: nil,
              preferences: input.preferences, modelInfo: "手動編集・旧形式"))
          }
          meeting.summary = summary.markdown
          meeting.keyPoints = summary.keyPoints
          meeting.decisions = summary.decisions
          meeting.openQuestions = summary.openQuestions
          meeting.status = .ready
          if let useCaseID { meeting.summaryUseCaseID = useCaseID.isEmpty ? nil : useCaseID }
          let version = TemplateSummary.snapshot(record: meeting, templateID: summary.templateID,
            preferences: input.preferences, modelInfo: engine == .cloud || engine == .memora ? llm.modelLabel : "端末内AI",
            evidence: summary.evidence)
          meeting.summaryVersions.append(version)
          meeting.activeSummaryVersionID = version.id
          meeting.privacy = meeting.effectivePrivacy
          if input.automaticCandidates.isEmpty, case .market(let template) = input.template {
            meeting.privacy.protect(template.sensitivityClassification)
          }
          if let selected = summary.templateID.flatMap(self.summaryChoice), case .market(let template) = selected {
            meeting.privacy.protect(template.sensitivityClassification)
          }
          candidateMeetings[index] = meeting
        }
        let extracted = self.extractedTasks(summary.actions, meetingID: id, meetingDate: current.createdAt)
        let candidateTasks = extracted + self.tasks
        let candidateJobs = self.pendingSummaryJobs.filter { $0.id != job.id }
        diagnostics.record(.saveStarted)
        self.updateMeetingTransiently(id) { $0.status = .organizing("結果を保存しています") }
        // Deliver the result and acknowledge the job in the same transaction.
        // A failed record write must never erase its only recoverable request.
        guard self.persistBatch({ [
          (key: StorageKey.meetings, data: try RecordStore.encoded(candidateMeetings)),
          (key: StorageKey.tasks, data: try RecordStore.encoded(candidateTasks)),
          (key: StorageKey.pendingSummaryJobs, data: try RecordStore.encoded(candidateJobs))
        ] }) else {
          diagnostics.record(.saveFailed)
          self.pauseBackgroundSummary(job, requiresUserRetry: true)
          return
        }
        self.meetingSearchTexts.removeValue(forKey: id)
        self.meetings = candidateMeetings
        self.tasks = candidateTasks
        self.pendingSummaryJobs = candidateJobs
        diagnostics.record(.saveCompleted)
        diagnostics.record(.completed)
        delivered = true
        self.scheduleBackgroundSummary()
        let added = extracted.count
        let permitsAutomaticDelivery = self.allowsRecordAccess(id, purpose: .automaticWebhook)
        if permitsAutomaticDelivery { self.deliverSummaryToWebhooks(id) }
        self.runResidentsAfterMeeting(id)
        self.offerPlusIfNeeded()
        self.announce(added > 0 ? "要約ができました。タスクを\(added)件追加しました。" : "要約ができました。")
      case .failure(.cancelled):
        diagnostics.record(.cancelled)
        // Cancelled without a newer request taking over: leave the record able
        // to be generated again rather than stuck mid-process.
        self.pauseBackgroundSummary(job, requiresUserRetry: true)
        return
      case .failure(let failure):
        diagnostics.failed(failure)
        if !self.summaryBackgroundScheduler.isForeground,
           [.connectionLost, .network, .timedOut, .engineNotReady, .assetsUnavailable].contains(failure) {
          self.pauseBackgroundSummary(job, requiresUserRetry: true)
          self.backgroundSummaryNotice = "バックグラウンドでの処理を中断しました。原文と設定は保存済みです。画面から再試行できます。"
          return
        }
        let message = failure == .empty ? "要約が空でした。もう一度お試しください。" : failure.message
        guard let index = self.meetings.firstIndex(where: { $0.id == id }) else { return }
        var candidateMeetings = self.meetings
        candidateMeetings[index].status = .failed(message)
        let candidateJobs = self.pendingSummaryJobs.filter { $0.id != job.id }
        guard self.persistBatch({ [
          (key: StorageKey.meetings, data: try RecordStore.encoded(candidateMeetings)),
          (key: StorageKey.pendingSummaryJobs, data: try RecordStore.encoded(candidateJobs))
        ] }) else {
          self.pauseBackgroundSummary(job, requiresUserRetry: true)
          return
        }
        self.meetings = candidateMeetings
        self.pendingSummaryJobs = candidateJobs
        self.scheduleBackgroundSummary()
        self.announce("要約を作成できませんでした。\(message)")
      }
      self.removeBackgroundSummary(meetingID: id, jobID: job.id)
    }
    activeSummaryRuns[job.id] = processing.runID(for: id)
    return true
  }
}
