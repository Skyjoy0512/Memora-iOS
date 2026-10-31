import BackgroundTasks
import UIKit

@MainActor
final class SystemSummaryBackgroundScheduler: SummaryBackgroundScheduling {
  private struct Run {
    var identifier: String
    var task: BGContinuedProcessingTask?
    var activity: BackgroundActivity
    var expire: @MainActor () -> Void
    var step = "文字起こしを整理しています"
    var events: Int64 = 0
  }
  private var runs: [UUID: Run] = [:]
  private var deferredRevision = UUID()
  private var registrationAttempted = false
  private var isRegistered = false
  private var bundleIdentifier: String?

  init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
    self.bundleIdentifier = bundleIdentifier
  }

  func registerContinuedProcessing() {
    guard !registrationAttempted, let bundleID = bundleIdentifier else { return }
    registrationAttempted = true
    // Register the same wildcard listed in Info.plist once, then route each unique request by its delivered ID.
    isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: bundleID + ".summaries.continued.*", using: .main) { [weak self] task in
      MainActor.assumeIsolated {
        guard let self else { task.setTaskCompleted(success: false); return }
        self.accept(task)
      }
    }
  }

  private func accept(_ task: BGTask) {
    guard let continued = task as? BGContinuedProcessingTask,
          let (jobID, run) = runs.first(where: { $0.value.identifier == task.identifier }), run.task == nil else {
      task.setTaskCompleted(success: false)
      return
    }
    runs[jobID]?.task = continued
    run.activity.end()
    continued.progress.totalUnitCount = -1
    continued.progress.completedUnitCount = run.events
    continued.updateTitle("要約を作成", subtitle: run.step)
    let identifier = run.identifier
    continued.expirationHandler = { [weak self] in
      Task { @MainActor in self?.expire(jobID, identifier: identifier) }
    }
    SummaryDiagnostics.recordBackground(jobID: jobID, stage: .backgroundGranted)
  }
  var isForeground: Bool { UIApplication.shared.applicationState == .active }

  func scheduleDeferred(requiresNetwork: Bool?, onFailure: @escaping @MainActor (String) -> Void) {
    let revision = UUID()
    deferredRevision = revision
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: MemoraModel.backgroundSummaryTaskID)
    guard let requiresNetwork else { return }
    let request = BGProcessingTaskRequest(identifier: MemoraModel.backgroundSummaryTaskID)
    request.requiresNetworkConnectivity = requiresNetwork
    request.requiresExternalPower = false
    submit(request) { [weak self] error in
      guard let self, self.deferredRevision == revision else { return }
      if error != nil { onFailure("iOSのバックグラウンド実行枠を予約できませんでした。記録は保存済みです。アプリに戻ると再試行できます。") }
    }
  }

  func begin(jobID: UUID, requestsContinuedProcessing: Bool, onExpiration: @escaping @MainActor () -> Void,
    onFailure: @escaping @MainActor (String) -> Void) {
    guard isForeground, runs[jobID] == nil, let bundleID = bundleIdentifier else { return }
    let identifier = bundleID + ".summaries.continued." + UUID().uuidString
    let activity = BackgroundActivity(name: "要約を作成") { [weak self] in
      guard let self, let run = self.runs[jobID], run.identifier == identifier,
            run.task == nil, !self.isForeground else { return }
      // Submission acceptance is not a lease. Stop the existing request when UIKit time ends.
      self.expire(jobID, identifier: identifier)
    }
    runs[jobID] = Run(identifier: identifier, activity: activity, expire: onExpiration)
    guard requestsContinuedProcessing else { return }
    registerContinuedProcessing()
    guard isRegistered else {
      SummaryDiagnostics.recordBackground(jobID: jobID, stage: .backgroundRejected, code: 0)
      onFailure("バックグラウンド要約を登録できませんでした。画面を開いた状態では処理を続けます。")
      return
    }
    let request = BGContinuedProcessingTaskRequest(identifier: identifier,
      title: "要約を作成", subtitle: "文字起こしを整理しています")
    // The foreground request starts immediately; iOS can extend that same run without replaying it.
    request.strategy = .fail
    SummaryDiagnostics.recordBackground(jobID: jobID, stage: .backgroundRequested)
    submit(request) { [weak self] error in
      guard let self, let run = self.runs[jobID], run.identifier == identifier else {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        return
      }
      if let error, run.task == nil {
        SummaryDiagnostics.recordBackground(jobID: jobID, stage: .backgroundRejected, code: (error as NSError).code)
        SummaryDiagnostics.recordBackground(jobID: jobID, stage: .backgroundFallback)
        onFailure("iOSが継続実行を許可しませんでした。画面を開いた状態では処理を続け、時間切れの場合は再試行待ちとして保存します。")
      } else if error == nil {
        SummaryDiagnostics.recordBackground(jobID: jobID, stage: .backgroundAccepted)
      }
    }
  }

  func report(jobID: UUID, step: String) {
    guard var run = runs[jobID] else { return }
    run.step = step
    run.events += 1
    runs[jobID] = run
    run.task?.updateTitle("要約を作成", subtitle: step)
    run.task?.progress.completedUnitCount = run.events
  }

  func finish(jobID: UUID, success: Bool) {
    guard let run = runs.removeValue(forKey: jobID) else { return }
    run.activity.end()
    if let task = run.task {
      task.expirationHandler = nil
      if success {
        task.progress.totalUnitCount = max(1, run.events)
        task.progress.completedUnitCount = task.progress.totalUnitCount
      }
      task.setTaskCompleted(success: success)
    } else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: run.identifier)
    }
  }

  private func expire(_ jobID: UUID, identifier: String) {
    guard let run = runs[jobID], run.identifier == identifier else { return }
    finish(jobID: jobID, success: false)
    run.expire()
  }

  private func submit(_ request: BGTaskRequest, completion: @escaping @MainActor (Error?) -> Void) {
    if #available(iOS 27.0, *) {
      // The 27 API reports asynchronous submission errors the old API misses.
      BGTaskScheduler.shared.submitTaskRequest(request) { error in
        Task { @MainActor in completion(error) }
      }
    } else {
      do { try BGTaskScheduler.shared.submit(request); completion(nil) }
      catch { completion(error) }
    }
  }
}
