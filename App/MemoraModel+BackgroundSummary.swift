import BackgroundTasks
import Foundation

extension MemoraModel {
  static let backgroundSummaryTaskID = "app.memora.summaries.processing"

  /// Keeps the summary parameters with the record, so a run cut short by the app
  /// leaving the foreground can be picked up again by the system.
  func enqueueBackgroundSummary(_ job: PendingSummaryJob) {
    guard !isRestoring, isStoreWritable() else { return }
    var jobs = pendingSummaryJobs.filter { $0.meetingID != job.meetingID }
    jobs.append(job)
    guard persistPendingSummaryJobs(jobs) else { return }
    pendingSummaryJobs = jobs
    scheduleBackgroundSummary()
  }

  static let autoSummaryAfterTranscriptionKey = "memora.summary.autoAfterTranscription"

  var automaticallySummarizesTranscriptions: Bool {
    UserDefaults.standard.bool(forKey: Self.autoSummaryAfterTranscriptionKey)
  }

  /// Queues the default summary after a transcript lands, when the person
  /// opted in. A record without cloud permission stays waiting instead of
  /// being sent to an external model.
  func enqueueAutomaticSummaryIfNeeded(for id: UUID) {
    guard automaticallySummarizesTranscriptions,
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
        usesCloud: usesCloud
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
    guard !pendingSummaryJobs.contains(where: { processing.isActive($0.meetingID) }) else { return }
    Task { _ = await runPendingBackgroundSummaries() }
  }

  func removeBackgroundSummary(meetingID: UUID) {
    let jobs = pendingSummaryJobs.filter { $0.meetingID != meetingID }
    guard jobs.count != pendingSummaryJobs.count else { return }
    guard persistPendingSummaryJobs(jobs) else { return }
    pendingSummaryJobs = jobs
    scheduleBackgroundSummary()
  }

  /// Asks the system for a processing window while a summary is still pending.
  /// The system decides when that window comes; an empty queue cancels the
  /// request so a finished summary does not wake the app.
  func scheduleBackgroundSummary() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundSummaryTaskID)
    let jobs = pendingSummaryJobs
    guard !jobs.isEmpty, currentTeamID == nil, !isRestoring, !isStoreProtected else { return }
    let request = BGProcessingTaskRequest(identifier: Self.backgroundSummaryTaskID)
    request.requiresNetworkConnectivity = jobs.contains { $0.usesCloud }
    request.requiresExternalPower = false
    request.earliestBeginDate = .now.addingTimeInterval(5)
    try? BGTaskScheduler.shared.submit(request)
  }

  func handleBackgroundSummary(_ task: BGProcessingTask) {
    // Keep the next pending job queued before this window is used.
    scheduleBackgroundSummary()
    let work = Task { [weak self] in
      let success = await self?.runPendingBackgroundSummaries() ?? false
      task.setTaskCompleted(success: success)
    }
    task.expirationHandler = { [weak self] in
      work.cancel()
      Task { @MainActor in self?.interruptBackgroundSummaries() }
    }
  }

  /// Runs the queued summaries one by one. A job is dropped only when its run
  /// reaches a terminal state, so a window cut short leaves the work for the
  /// next one instead of losing it.
  func runPendingBackgroundSummaries() async -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected else { return false }
    for job in pendingSummaryJobs {
      guard !Task.isCancelled else { return false }
      guard let meeting = meeting(id: job.meetingID), !meeting.transcript.isEmpty else {
        removeBackgroundSummary(meetingID: job.meetingID)
        continue
      }
      if meeting.status == .ready {
        removeBackgroundSummary(meetingID: job.meetingID)
        continue
      }

      generateSummary(
        job.meetingID,
        choice: job.choice,
        configuration: (job.engine, job.llm),
        automaticallySelect: job.automaticallySelect,
        useCaseID: job.useCaseID,
        preferences: job.preferences,
        cloudDisclosureConfirmed: job.cloudDisclosureConfirmed
      )

      guard await waitForSummary(job.meetingID) else {
        interruptBackgroundSummary(job.meetingID)
        return false
      }
      removeBackgroundSummary(meetingID: job.meetingID)
    }
    scheduleBackgroundSummary()
    return true
  }

  /// The summary itself is run by `ProcessingService`; this waits for that run
  /// to settle. The bound keeps a broken job from holding the whole window.
  private func waitForSummary(_ id: UUID) async -> Bool {
    for _ in 0..<540 {
      guard !Task.isCancelled else { return false }
      if !processing.isActive(id) { return true }
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return false
      }
    }
    return false
  }

  private func interruptBackgroundSummaries() {
    for job in pendingSummaryJobs {
      interruptBackgroundSummary(job.meetingID)
    }
    scheduleBackgroundSummary()
  }

  /// Stops the processing task and puts the record back where it can be retried
  /// instead of leaving the spinner on screen.
  private func interruptBackgroundSummary(_ id: UUID) {
    guard processing.isActive(id) else { return }
    processing.cancel(id)
    updateMeeting(id) { meeting in
      if case .organizing = meeting.status {
        meeting.status = .waitingForSummary
      }
    }
  }

  private func persistPendingSummaryJobs(_ jobs: [PendingSummaryJob]) -> Bool {
    persistNow(jobs, forKey: StorageKey.pendingSummaryJobs)
  }
}
