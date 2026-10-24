import Foundation

/// Only the OS boundary is substituted in host checks; the queue and the
/// summary's processing/persistence paths remain production code.
@MainActor
protocol SummaryBackgroundScheduling: AnyObject {
  var isForeground: Bool { get }
  func scheduleDeferred(requiresNetwork: Bool?, onFailure: @escaping @MainActor (String) -> Void)
  func begin(jobID: UUID, requestsContinuedProcessing: Bool, onExpiration: @escaping @MainActor () -> Void,
    onFailure: @escaping @MainActor (String) -> Void)
  func report(jobID: UUID, step: String)
  func finish(jobID: UUID, success: Bool)
}
