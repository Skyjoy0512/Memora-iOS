import Foundation

extension MemoraModel {
  static let backgroundSummaryTaskID = "app.memora.summaries.processing"

  /// Keeps the summary parameters with the record, so a run cut short by the app
  /// leaving the foreground can be picked up again by the system.
  @discardableResult
  func enqueueBackgroundSummary(_ job: PendingSummaryJob) -> Bool {
    guard currentTeamID == nil, !isRestoring, isStoreWritable() else { return false }
    var jobs = pendingSummaryJobs.filter { $0.meetingID != job.meetingID }
    jobs.append(job)
    guard persistPendingSummaryJobs(jobs) else { return false }
    pendingSummaryJobs = jobs
    scheduleBackgroundSummary()
    return true
  }

  static let autoSummaryAfterTranscriptionKey = "memora.summary.autoAfterTranscription"

  func recordSummaryLifecycle() {
    let active = Set(pendingSummaryJobs.filter { processing.isActive($0.meetingID) }.map(\.id))
    SummaryDiagnostics.recordLifecycle(jobIDs: active, isForeground: summaryBackgroundScheduler.isForeground)
  }

  var automaticallySummarizesTranscriptions: Bool {
    UserDefaults.standard.bool(forKey: Self.autoSummaryAfterTranscriptionKey)
  }

  /// Queues the default summary after a transcript lands, when the person
  /// opted in. A record without cloud permission stays waiting instead of
  /// being sent to an external model.
  func enqueueAutomaticSummaryIfNeeded(for id: UUID, required: Bool = false) {
    guard (required || automaticallySummarizesTranscriptions),
          let meeting = meeting(id: id), !meeting.transcript.isEmpty,
          !hasPendingSummary(id) else { return }
    let configuration = settingsAIConfiguration
    let effective = AIEngineService.effectiveEngine(configuration.engine)
    let usesCloud = effective == .cloud || effective == .memora
    if usesCloud,
       !RecordAccessPolicy.allows(meeting.effectivePrivacy, purpose: .cloudAI, explicitCloudConsent: false) {
      return
    }
    let useCaseID = meeting.summaryUseCaseID
    enqueueBackgroundSummary(
      PendingSummaryJob(
        meetingID: id,
        choice: automaticSummaryChoice(for: meeting, useCaseID: useCaseID),
        engineRawValue: configuration.engine.rawValue,
        llm: configuration.llm,
        automaticallySelect: summaryPreferences.method == .automatic && (useCaseID ?? "").isEmpty,
        useCaseID: useCaseID,
        preferences: summaryPreferences,
        cloudDisclosureConfirmed: false,
        usesCloud: usesCloud,
        inputFingerprint: SummaryJobFingerprint.make(meeting)
      )
    )
    // The transcription job is still finishing when this is called; let it
    // release the record before the summary takes the same slot.
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      self?.resumePendingSummariesIfNeeded()
    }
  }

  func hasPendingSummary(_ meetingID: UUID) -> Bool {
    pendingSummaryJobs.contains { $0.meetingID == meetingID }
  }

  /// Finishes a queued summary when the app comes back to the foreground, in
  /// case iOS did not run the processing window. The same job is used, so the
  /// result and its checks match a background run.
  func resumePendingSummariesIfNeeded() {
    guard !pendingSummaryJobs.isEmpty, currentTeamID == nil,
          !isRestoring, !isStoreProtected else { return }
    guard summaryQueueRunID == nil else { return }
    Task { _ = await runPendingBackgroundSummaries() }
  }

  func removeBackgroundSummary(meetingID: UUID, jobID: UUID? = nil) {
    let jobs = pendingSummaryJobs.filter { $0.meetingID != meetingID || (jobID != nil && $0.id != jobID) }
    guard jobs.count != pendingSummaryJobs.count else { return }
    guard persistPendingSummaryJobs(jobs) else { return }
    pendingSummaryJobs = jobs
    scheduleBackgroundSummary()
  }

  /// Asks the system for a processing window while a summary is still pending.
  /// The system decides when that window comes; an empty queue cancels the
  /// request so a finished summary does not wake the app.
  func scheduleBackgroundSummary() {
    let jobs = pendingSummaryJobs.filter { !$0.cloudDisclosureConfirmed && $0.requiresUserRetry != true && $0.attemptStartedAt == nil && $0.inputFingerprint != nil }
    let permitted = !jobs.isEmpty && currentTeamID == nil && !isRestoring && !isStoreProtected
    summaryBackgroundScheduler.scheduleDeferred(requiresNetwork: permitted ? jobs.contains { $0.usesCloud } : nil) { [weak self] message in
      self?.backgroundSummaryNotice = message
    }
  }

  /// Runs the queued summaries one by one. A job is dropped only when its run
  /// reaches a terminal state, so a window cut short leaves the work for the
  /// next one instead of losing it.
  func runPendingBackgroundSummaries() async -> Bool {
    guard summaryQueueRunID == nil, currentTeamID == nil, !isRestoring, !isStoreProtected else { return false }
    let token = UUID()
    let generation = aiWorkspaceGeneration
    summaryQueueRunID = token
    defer { if summaryQueueRunID == token { summaryQueueRunID = nil }; scheduleBackgroundSummary() }
    var allSucceeded = true
    for job in pendingSummaryJobs {
      guard !Task.isCancelled, generation == aiWorkspaceGeneration, currentTeamID == nil,
            !isRestoring, !isStoreProtected else { return false }
      guard pendingSummaryJobs.contains(where: { $0.id == job.id }), job.requiresUserRetry != true,
            job.attemptStartedAt == nil else { continue }
      guard let meeting = meeting(id: job.meetingID), !meeting.transcript.isEmpty else {
        removeBackgroundSummary(meetingID: job.meetingID, jobID: job.id)
        continue
      }
      if processing.isActive(job.meetingID) { continue }
      // A persisted checkbox or user gesture is never a new send instruction.
      if job.cloudDisclosureConfirmed {
        pauseBackgroundSummary(job, requiresUserRetry: true)
        continue
      }
      guard let fingerprint = job.inputFingerprint, fingerprint == SummaryJobFingerprint.make(meeting) else {
        pauseBackgroundSummary(job, requiresUserRetry: true)
        continue
      }

      let started = generateSummary(
        job.meetingID,
        choice: job.choice,
        configuration: (job.engine, job.llm),
        automaticallySelect: job.automaticallySelect,
        useCaseID: job.useCaseID,
        preferences: job.preferences,
        pendingJob: job
      )
      guard started else { pauseBackgroundSummary(job, requiresUserRetry: true); continue }

      guard await waitForSummary(job, generation: generation) else {
        pauseBackgroundSummary(job, requiresUserRetry: true)
        return false
      }
      if self.meeting(id: job.meetingID)?.status != .ready { allSucceeded = false }
      // Completion, not the waiter, owns removal. A stopped task, failed save
      // or a replacement run must never be mistaken for a delivered summary.
    }
    return pendingSummaryJobs.isEmpty && allSucceeded
  }

  /// The summary itself is run by `ProcessingService`; this waits for that run
  /// to settle. The bound keeps a broken job from holding the whole window.
  private func waitForSummary(_ job: PendingSummaryJob, generation: UUID) async -> Bool {
    var elapsedSeconds = 0
    // The deferred OS window has a bound; foreground inference does not inherit
    // that waiter's deadline (a long multi-part summary can need more time).
    while elapsedSeconds < 540 || summaryBackgroundScheduler.isForeground {
      guard !Task.isCancelled, currentTeamID == nil, aiWorkspaceGeneration == generation,
            !isRestoring, !isStoreProtected else { return false }
      guard pendingSummaryJobs.contains(where: { $0.id == job.id }) else { return true }
      guard activeSummaryRuns[job.id] == processing.runID(for: job.meetingID) else { return true }
      if !processing.isActive(job.meetingID) { return true }
      do {
        try await Task.sleep(for: .seconds(1))
        elapsedSeconds += 1
      } catch {
        return false
      }
    }
    return false
  }

  func interruptPendingSummaries(requiresUserRetry: Bool) {
    for job in pendingSummaryJobs {
      pauseBackgroundSummary(job, requiresUserRetry: requiresUserRetry)
    }
    scheduleBackgroundSummary()
  }

  /// Stops the processing task and puts the record back where it can be retried
  /// instead of leaving the spinner on screen.
  func pauseBackgroundSummary(_ job: PendingSummaryJob, requiresUserRetry: Bool) {
    guard let index = pendingSummaryJobs.firstIndex(where: { $0.id == job.id }) else { return }
    if let run = activeSummaryRuns.removeValue(forKey: job.id), processing.runID(for: job.meetingID) == run {
      processing.cancel(job.meetingID)
    }
    summaryBackgroundScheduler.finish(jobID: job.id, success: false)
    var jobs = pendingSummaryJobs
    jobs[index].requiresUserRetry = requiresUserRetry || jobs[index].requiresUserRetry == true || jobs[index].attemptStartedAt != nil
    _ = persistPendingSummaryJobs(jobs)
    pendingSummaryJobs = jobs
    updateMeeting(job.meetingID) { meeting in
      if case .organizing = meeting.status {
        meeting.status = .waitingForSummary
      }
    }
  }

  func recoverCancelledSummaryRuns() {
    let interrupted = pendingSummaryJobs.filter { job in
      guard let run = activeSummaryRuns[job.id] else { return false }
      return processing.runID(for: job.meetingID) != run
    }
    for job in interrupted { pauseBackgroundSummary(job, requiresUserRetry: true) }
  }

  private func persistPendingSummaryJobs(_ jobs: [PendingSummaryJob]) -> Bool {
    persistNow(jobs, forKey: StorageKey.pendingSummaryJobs)
  }
}
