import Foundation
import SQLite3

@main
enum BackgroundSummaryExecutionChecks {
  @MainActor static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("summary-execution-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var number = 0
    func model() throws -> MemoraModel {
      number += 1
      let value = try MemoraModel(url: root.appendingPathComponent("\(number).sqlite"))
      value.meetings = [Meeting()]
      precondition(value.persistNow(value.meetings, forKey: MemoraModel.StorageKey.meetings))
      precondition(value.persistNow(value.tasks, forKey: MemoraModel.StorageKey.tasks))
      return value
    }
    func read<T: Decodable>(_ model: MemoraModel, _ key: String, as: T.Type) throws -> T {
      guard case .data(let data) = model.store.readOutcome(key) else { preconditionFailure("missing fixture document") }
      return try JSONDecoder().decode(T.self, from: data)
    }
    func start(_ model: MemoraModel) async -> MeetingSummarizer.Request {
      precondition(model.generateSummary(model.meetings[0].id, choice: .standard, cloudDisclosureConfirmed: true))
      for _ in 0..<1000 {
        if !MeetingSummarizer.requests.isEmpty { return MeetingSummarizer.requests.removeFirst() }
        await Task.yield()
      }
      preconditionFailure("inference not started")
    }
    func settle(_ model: MemoraModel) async throws {
      for _ in 0..<1000 {
        if model.processing.activeIDs.isEmpty { return }
        try await Task.sleep(for: .milliseconds(1))
      }
      preconditionFailure("processing did not settle")
    }
    let result = MeetingSummary(markdown: "# 検証結果\n公開は承認後。", actions: [
      SummaryActionItem(title: "承認を確認", owner: nil, due: nil),
      SummaryActionItem(title: "承認を確認", owner: nil, due: nil)
    ])

    // Empty segments are possible after editing; no inference/job/status write.
    let empty = try MemoraModel(url: root.appendingPathComponent("empty.sqlite"))
    empty.meetings = [Meeting()]
    empty.meetings[0].transcript[0].text = " \n\t　"
    precondition(!empty.generateSummary(empty.meetings[0].id, choice: .standard, cloudDisclosureConfirmed: true))
    precondition(empty.pendingSummaryJobs.isEmpty && empty.processing.activeIDs.isEmpty && MeetingSummarizer.requests.isEmpty)
    precondition(empty.meetings[0].summary == "保存済みの旧要約")

    // Actual generation -> ProcessingService -> atomic commit -> SQLite reopen.
    let success = try model()
    let request = await start(success)
    let startedJob = success.pendingSummaryJobs[0]
    let inFlight = try read(success, MemoraModel.StorageKey.pendingSummaryJobs, as: [PendingSummaryJob].self)
    precondition(inFlight[0].attemptStartedAt != nil && inFlight[0].requiresUserRetry == true,
      "Process termination could automatically resend a billed request")
    precondition(success.scheduler.starts == [startedJob.id])
    precondition(success.scheduler.continuedRequests == [true])
    request.progress("実際の出力を受信")
    precondition(success.scheduler.steps == ["実際の出力を受信"])
    request.complete.resume(returning: .success(result))
    try await settle(success)
    let reopened = LocalStore(fileURL: root.appendingPathComponent("1.sqlite"))
    try reopened.prepare()
    guard case .data(let persisted) = reopened.readOutcome(MemoraModel.StorageKey.meetings) else { fatalError() }
    let saved = try JSONDecoder().decode([Meeting].self, from: persisted)
    precondition(saved[0].summary == result.markdown && saved[0].summaryVersions.count == 2)
    precondition(saved[0].transcript[0].text == "承認前には公開しない。")
    let savedTasks = try read(success, MemoraModel.StorageKey.tasks, as: [MemoraTask].self)
    let savedJobs = try read(success, MemoraModel.StorageKey.pendingSummaryJobs, as: [PendingSummaryJob].self)
    precondition(savedTasks.count == 1 && savedTasks[0].assignee == nil && savedTasks[0].dueDate == nil && savedJobs.isEmpty)
    precondition(success.deliveries == 1 && success.scheduler.finishes.last?.1 == true)

    // A denied task write rolls back the summary and the queue acknowledgement.
    let failed = try model()
    let failedRequest = await start(failed)
    var db: OpaquePointer?
    precondition(sqlite3_open(root.appendingPathComponent("2.sqlite").path, &db) == SQLITE_OK)
    precondition(sqlite3_exec(db, "CREATE TRIGGER fail_summary BEFORE INSERT ON documents WHEN NEW.key='memoraTasks' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END;", nil, nil, nil) == SQLITE_OK)
    failedRequest.complete.resume(returning: .success(result))
    try await settle(failed)
    let rolledBack = try read(failed, MemoraModel.StorageKey.meetings, as: [Meeting].self)
    let recoverable = try read(failed, MemoraModel.StorageKey.pendingSummaryJobs, as: [PendingSummaryJob].self)
    precondition(rolledBack[0].summary == "保存済みの旧要約" && recoverable.count == 1 && failed.tasks.isEmpty)
    precondition(failed.meetings[0].status == .waitingForSummary && recoverable[0].requiresUserRetry == true && failed.deliveries == 0)
    sqlite3_close(db)

    // OS expiry/user cancel retains the job and prevents automatic paid replay.
    let expired = try model()
    let expiredRequest = await start(expired)
    let expiredJob = expired.pendingSummaryJobs[0]
    expired.scheduler.expirations[expiredJob.id]?()
    precondition(!expired.processing.isActive(expiredJob.meetingID) && expired.pendingSummaryJobs[0].requiresUserRetry == true)
    _ = await expired.runPendingBackgroundSummaries()
    precondition(MeetingSummarizer.requests.isEmpty)
    let replacement = await start(expired)
    let replacementJob = expired.pendingSummaryJobs[0]
    expired.scheduler.expirations[expiredJob.id]?()
    expiredRequest.complete.resume(returning: .success(result))
    await Task.yield()
    precondition(expired.processing.isActive(replacementJob.meetingID) && expired.pendingSummaryJobs[0].id == replacementJob.id)
    replacement.complete.resume(returning: .success(result))
    try await settle(expired)

    // The old summary's deadline cannot cancel a different operation that
    // subsequently acquired the same record's ProcessingService slot.
    let ownership = try model()
    let oldRequest = await start(ownership)
    let oldJob = ownership.pendingSummaryJobs[0]
    ownership.processing.cancel(oldJob.meetingID)
    var other: CheckedContinuation<Int, Never>?
    ownership.processing.run(id: oldJob.meetingID) {
      await withCheckedContinuation { other = $0 }
    } apply: { _ in }
    while other == nil { await Task.yield() }
    ownership.pauseBackgroundSummary(oldJob, requiresUserRetry: true)
    precondition(ownership.processing.isActive(oldJob.meetingID))
    oldRequest.complete.resume(returning: .success(result))
    await Task.yield()
    precondition(ownership.processing.isActive(oldJob.meetingID))
    other?.resume(returning: 1)
    try await settle(ownership)

    // Background network interruption is not a terminal failure or silent retry.
    let network = try model()
    let networkRequest = await start(network)
    network.scheduler.isForeground = false
    networkRequest.complete.resume(returning: .failure(.connectionLost))
    try await settle(network)
    precondition(network.meetings[0].status == .waitingForSummary && network.pendingSummaryJobs.count == 1)
    precondition(network.pendingSummaryJobs[0].requiresUserRetry == true && network.backgroundSummaryNotice != nil)

    // In-flight edits/permissions/workspace ABA must never publish stale output.
    for mutate in 0..<6 {
      let changed = try model()
      let pending = await start(changed)
      switch mutate {
      case 0: changed.meetings[0].transcript[0].text = "訂正した原文"
      case 1: changed.meetings[0].summary = "本人の手編集"
      case 2: changed.meetings[0].privacy.revokeExternalPermissions()
      case 3: changed.aiWorkspaceGeneration = UUID()
      case 4: changed.isRestoring = true
      default: changed.meetings[0].spaceID = UUID()
      }
      pending.complete.resume(returning: .success(result))
      try await settle(changed)
      precondition(changed.meetings[0].summary != result.markdown && changed.pendingSummaryJobs.count == 1 && changed.tasks.isEmpty)
    }

    // Single-flight queue uses the persisted job ID, never enqueues a duplicate.
    let queued = try model()
    let original = await start(queued)
    let attemptedJob = queued.pendingSummaryJobs[0]
    queued.pauseBackgroundSummary(attemptedJob, requiresUserRetry: false)
    original.complete.resume(returning: .failure(.cancelled))
    await Task.yield()
    _ = await queued.runPendingBackgroundSummaries()
    precondition(MeetingSummarizer.requests.isEmpty && queued.pendingSummaryJobs[0].requiresUserRetry == true)
    let queueJob = PendingSummaryJob(meetingID: queued.meetings[0].id, choice: .standard,
      engineRawValue: AIEngine.cloud.rawValue, llm: queued.settingsAIConfiguration.llm,
      automaticallySelect: false, preferences: SummaryPreferences(), cloudDisclosureConfirmed: true,
      usesCloud: true, inputFingerprint: SummaryJobFingerprint.make(queued.meetings[0]))
    precondition(queued.enqueueBackgroundSummary(queueJob))
    let run = Task { await queued.runPendingBackgroundSummaries() }
    while MeetingSummarizer.requests.isEmpty { await Task.yield() }
    precondition(queued.pendingSummaryJobs.count == 1 && queued.pendingSummaryJobs[0].id == queueJob.id)
    precondition(queued.scheduler.continuedRequests == [true, false])
    let duplicate = await queued.runPendingBackgroundSummaries()
    precondition(!duplicate)
    MeetingSummarizer.requests.removeFirst().complete.resume(returning: .success(result))
    let queueCompleted = await run.value
    precondition(queueCompleted)

    // Legacy and changed jobs require fresh confirmation, including disclosure.
    for legacy in [true, false] {
      let stale = try model()
      let pending = await start(stale)
      let job = stale.pendingSummaryJobs[0]
      stale.pauseBackgroundSummary(job, requiresUserRetry: false)
      var unstarted = job
      unstarted.attemptStartedAt = nil
      unstarted.requiresUserRetry = nil
      precondition(stale.enqueueBackgroundSummary(unstarted))
      if legacy { stale.pendingSummaryJobs[0].inputFingerprint = nil }
      else { stale.meetings[0].transcript[0].text = "新しい内容" }
      pending.complete.resume(returning: .failure(.cancelled))
      await Task.yield()
      _ = await stale.runPendingBackgroundSummaries()
      precondition(MeetingSummarizer.requests.isEmpty && stale.pendingSummaryJobs[0].requiresUserRetry == true)
    }
    let refused = try model()
    refused.scheduler.failSubmission = true
    let fallback = await start(refused)
    precondition(refused.backgroundSummaryNotice != nil && refused.processing.isActive(refused.meetings[0].id))
    fallback.complete.resume(returning: .success(result))
    try await settle(refused)
    precondition(refused.pendingSummaryJobs.isEmpty)

    let missingKey = try model()
    let missingRequest = await start(missingKey)
    missingKey.scheduler.isForeground = false
    missingRequest.complete.resume(returning: .failure(.missingKey))
    try await settle(missingKey)
    guard case .failed = missingKey.meetings[0].status else { preconditionFailure("missing key was hidden as pending") }
    precondition(missingKey.pendingSummaryJobs.isEmpty)

    let queueFailure = try model()
    let queuedFailureJob = PendingSummaryJob(meetingID: queueFailure.meetings[0].id, choice: .standard,
      engineRawValue: AIEngine.cloud.rawValue, llm: queueFailure.settingsAIConfiguration.llm,
      automaticallySelect: false, preferences: SummaryPreferences(), cloudDisclosureConfirmed: true,
      usesCloud: true, inputFingerprint: SummaryJobFingerprint.make(queueFailure.meetings[0]))
    precondition(queueFailure.enqueueBackgroundSummary(queuedFailureJob))
    let failingWindow = Task { await queueFailure.runPendingBackgroundSummaries() }
    while MeetingSummarizer.requests.isEmpty { await Task.yield() }
    MeetingSummarizer.requests.removeFirst().complete.resume(returning: .failure(.missingKey))
    let windowSucceeded = await failingWindow.value
    precondition(!windowSucceeded && queueFailure.pendingSummaryJobs.isEmpty)

    // A queue persistence failure must not start inference or discard input.
    let unsaved = try model()
    var unsavedDB: OpaquePointer?
    precondition(sqlite3_open(root.appendingPathComponent("\(number).sqlite").path, &unsavedDB) == SQLITE_OK)
    precondition(sqlite3_exec(unsavedDB, "CREATE TRIGGER fail_enqueue BEFORE INSERT ON documents WHEN NEW.key='memoraPendingSummaryJobs' BEGIN SELECT RAISE(ABORT, 'fixture enqueue failure'); END;", nil, nil, nil) == SQLITE_OK)
    let accepted = unsaved.generateSummary(unsaved.meetings[0].id, choice: .standard, cloudDisclosureConfirmed: true)
    precondition(!accepted && unsaved.pendingSummaryJobs.isEmpty && !unsaved.processing.isActive(unsaved.meetings[0].id))
    precondition(unsaved.meetings[0].summary == "保存済みの旧要約" && MeetingSummarizer.requests.isEmpty)
    sqlite3_close(unsavedDB)
    print("BackgroundSummaryExecutionChecks: passed (production queue/generation/cancellation, real SQLite atomic save and reopen; OS/model are fixtures)")
  }
}
