import Foundation

@main
enum RecordingRunCoordinatorChecks {
  static func main() {
    var run = RecordingRunCoordinator()
    precondition(run.phase == .idle && run.runID == nil && !run.isActive)

    // Normal lifecycle: idle → preparing → recording → stopping → finalizing → saved.
    guard let first = run.begin() else { preconditionFailure("begin refused from idle") }
    precondition(run.phase == .preparing && run.owns(first) && run.isActive)
    precondition(run.begin() == nil, "a second start must be refused while preparing")
    precondition(run.markRecording(first))
    precondition(run.phase == .recording)
    precondition(run.beginStopping(first))
    precondition(run.phase == .stopping)
    precondition(run.beginFinalizing(first))
    precondition(run.phase == .finalizing)
    precondition(run.markSaved(first))
    precondition(run.phase == .saved && run.runID == nil && !run.isActive)
    // A late callback from the finished run cannot move a new one.
    precondition(!run.beginStopping(first))
    precondition(!run.fail(first, reason: "late"))
    precondition(!run.cancel(first))

    // The finished run may be replaced.
    run.reset()
    precondition(run.phase == .idle && run.runID == nil)
    guard let second = run.begin() else { preconditionFailure("begin refused after saved") }
    precondition(second != first && run.owns(second))
    precondition(run.cancel(second))
    run.reset()
    precondition(run.phase == .idle && run.runID == nil)

    // Failures are allowed at every active phase and stop the run.
    for phase in 0...3 {
      var failing = RecordingRunCoordinator()
      guard let id = failing.begin() else { preconditionFailure("begin") }
      if phase >= 1 { precondition(failing.markRecording(id)) }
      if phase >= 2 { precondition(failing.beginStopping(id)) }
      if phase >= 3 { precondition(failing.beginFinalizing(id)) }
      precondition(failing.fail(id, reason: "storage"))
      precondition(failing.phase == .failed("storage") && failing.isFailure && !failing.isActive)
      precondition(failing.runID == nil)
      // A failed run can be started again, and saved/failed/cancelled reset to idle.
      guard let retry = failing.begin() else { preconditionFailure("begin refused after failure") }
      precondition(failing.runID == retry)
    }

    // A stale run id cannot touch the current run.
    var replacing = RecordingRunCoordinator()
    guard let stale = replacing.begin() else { preconditionFailure("begin") }
    _ = replacing.cancel(stale)
    guard let current = replacing.begin() else { preconditionFailure("begin after cancel") }
    precondition(replacing.phase == .preparing && replacing.runID == current)
    precondition(!replacing.markRecording(stale))
    precondition(!replacing.beginStopping(stale))
    precondition(!replacing.beginFinalizing(stale))
    precondition(!replacing.markSaved(stale))
    precondition(!replacing.fail(stale, reason: "late"))
    precondition(!replacing.cancel(stale))
    precondition(replacing.phase == .preparing && replacing.runID == current)
    precondition(replacing.markRecording(current))

    // Cancelling mid-recording also returns to a reusable state.
    var cancelled = RecordingRunCoordinator()
    guard let cancelledID = cancelled.begin() else { preconditionFailure("begin") }
    precondition(cancelled.markRecording(cancelledID))
    precondition(cancelled.cancel(cancelledID))
    precondition(cancelled.phase == .cancelled && !cancelled.isActive && cancelled.runID == nil)
    precondition(cancelled.begin() != nil)

    // Double stop: once saved, a repeated stop cannot re-enter stopping.
    var doubleStop = RecordingRunCoordinator()
    guard let stopID = doubleStop.begin() else { preconditionFailure("begin") }
    precondition(doubleStop.markRecording(stopID))
    precondition(doubleStop.beginStopping(stopID))
    precondition(doubleStop.beginFinalizing(stopID))
    precondition(doubleStop.markSaved(stopID))
    precondition(!doubleStop.beginStopping(stopID))
    precondition(!doubleStop.markSaved(stopID))

    // reset() must not interrupt an active run.
    var guarded = RecordingRunCoordinator()
    guard let guardedID = guarded.begin() else { preconditionFailure("begin") }
    guarded.reset()
    precondition(guarded.phase == .preparing && guarded.runID == guardedID)

    print("RecordingRunCoordinatorChecks: passed (full lifecycle, double start/stop, stale run IDs, failure at each active phase, cancel and guarded reset)")
  }
}
