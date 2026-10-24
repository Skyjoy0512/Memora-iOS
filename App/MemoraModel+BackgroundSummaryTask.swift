import BackgroundTasks
import Foundation

extension MemoraModel {
  func handleBackgroundSummary(_ task: BGProcessingTask) {
    // An OS window never takes ownership of a run already started by the user.
    // Otherwise its expiry could cancel unrelated foreground work.
    guard summaryQueueRunID == nil, !pendingSummaryJobs.contains(where: { processing.isActive($0.meetingID) }) else {
      task.setTaskCompleted(success: false)
      return
    }
    let work = Task { [weak self] in
      let success = await self?.runPendingBackgroundSummaries() ?? false
      task.expirationHandler = nil
      task.setTaskCompleted(success: success)
    }
    task.expirationHandler = {
      // The cancelled waiter pauses only the exact job it owns. Never cancel
      // every record here: a newer foreground run may already have replaced it.
      work.cancel()
    }
  }
}
