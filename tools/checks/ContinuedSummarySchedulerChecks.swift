import Foundation

// Only UIKit/BackgroundTasks are substituted; the scheduler is production code.
@main struct ContinuedSummarySchedulerChecks {
  @MainActor static func main() async {
    let scheduler = SystemSummaryBackgroundScheduler(bundleIdentifier: "app.memora.fixture")
    scheduler.registerContinuedProcessing()
    scheduler.registerContinuedProcessing()
    precondition(BGTaskScheduler.shared.registrations == ["app.memora.fixture.summaries.continued.*"])
    var failures: [String] = [], expirations: [UUID] = []
    func begin() -> (UUID, String) {
      let job = UUID()
      scheduler.begin(jobID: job, requestsContinuedProcessing: true,
        onExpiration: { expirations.append(job) }, onFailure: { failures.append($0) })
      let request = BGTaskScheduler.shared.requests.last as! BGContinuedProcessingTaskRequest
      precondition(request.strategy == .fail)
      return (job, request.identifier)
    }
    let (job, id) = begin()
    BGTaskScheduler.shared.resolve(id, error: nil)
    await drain()
    let grace = BackgroundActivity.all.last!
    let task = BGTaskScheduler.shared.deliver(id)
    precondition(grace.ended)
    UIApplication.shared.applicationState = .background
    grace.expire()
    precondition(expirations.isEmpty, "UIKit expiry cancelled an already delivered continued lease")
    scheduler.report(jobID: job, step: "実際の出力を受信")
    precondition(task.progress.completedUnitCount == 1 && task.progress.totalUnitCount == -1)
    let lateExpiration = task.expirationHandler
    scheduler.finish(jobID: job, success: true)
    precondition(task.completions == [true] && task.progress.isFinished)
    lateExpiration?()
    await drain()
    precondition(expirations.isEmpty)

    // Accepted submission without a delivered lease does not extend execution time.
    UIApplication.shared.applicationState = .active
    let (undelivered, undeliveredID) = begin()
    BGTaskScheduler.shared.resolve(undeliveredID, error: nil)
    await drain()
    UIApplication.shared.applicationState = .background
    BackgroundActivity.all.last!.expire()
    precondition(expirations == [undelivered])
    precondition(BGTaskScheduler.shared.cancellations.contains(undeliveredID))
    precondition(BGTaskScheduler.shared.deliver(undeliveredID).completions == [false])

    UIApplication.shared.applicationState = .active
    let (cancelled, oldID) = begin()
    scheduler.finish(jobID: cancelled, success: false)
    let (replacement, replacementID) = begin()
    precondition(oldID != replacementID)
    precondition(BGTaskScheduler.shared.deliver(oldID).completions == [false])
    BGTaskScheduler.shared.resolve(oldID, error: NSError(domain: "fixture", code: 1))
    await drain()
    precondition(failures.isEmpty)
    let live = BGTaskScheduler.shared.deliver(replacementID)
    live.expirationHandler?()
    await drain()
    precondition(expirations.contains(replacement) && live.completions == [false])
    scheduler.finish(jobID: replacement, success: false)
    precondition(live.completions == [false], "completed one OS task twice")

    let (fallback, fallbackID) = begin()
    BGTaskScheduler.shared.resolve(fallbackID, error: NSError(domain: "fixture", code: 2))
    await drain()
    precondition(failures.count == 1)
    UIApplication.shared.applicationState = .background
    BackgroundActivity.all.last!.expire()
    precondition(expirations.contains(fallback))

    UIApplication.shared.applicationState = .active
    let automatic = UUID()
    let previous = BGTaskScheduler.shared.requests.count
    scheduler.begin(jobID: automatic, requestsContinuedProcessing: false,
      onExpiration: {}, onFailure: { _ in preconditionFailure() })
    precondition(BGTaskScheduler.shared.requests.count == previous, "automatic job requested a user-only lease")
    scheduler.finish(jobID: automatic, success: false)

    let (first, firstID) = begin()
    let (second, secondID) = begin()
    let secondTask = BGTaskScheduler.shared.deliver(secondID)
    scheduler.finish(jobID: second, success: true)
    precondition(secondTask.completions == [true])
    let firstTask = BGTaskScheduler.shared.deliver(firstID)
    precondition(firstTask.completions.isEmpty)
    scheduler.finish(jobID: first, success: false)
    precondition(firstTask.completions == [false])

    BGTaskScheduler.shared.registrationSucceeds = false
    let unregistered = SystemSummaryBackgroundScheduler(bundleIdentifier: "app.memora.registration-fixture")
    let rejectedJob = UUID()
    var registrationFailure = false
    unregistered.begin(jobID: rejectedJob, requestsContinuedProcessing: true,
      onExpiration: {}, onFailure: { _ in registrationFailure = true })
    precondition(registrationFailure)
    unregistered.finish(jobID: rejectedJob, success: false)
    print("ContinuedSummarySchedulerChecks passed: immediate strategy, delivered lease handoff, undelivered lease expiry, cancellation, late callbacks, isolation, fallback, automatic policy; OS APIs are fixtures")
  }
  @MainActor static func drain() async { for _ in 0..<30 { await Task.yield() } }
}

final class UIApplication {
  enum State { case active, background }
  static let shared = UIApplication()
  var applicationState = State.active
}
class BGTask {
  var identifier: String
  var expirationHandler: (() -> Void)?
  var completions: [Bool] = []
  init(_ identifier: String) { self.identifier = identifier }
  func setTaskCompleted(success: Bool) { completions.append(success) }
}
final class BGContinuedProcessingTask: BGTask {
  var progress = Progress(totalUnitCount: -1)
  func updateTitle(_ title: String, subtitle: String) {}
}
class BGTaskRequest {
  var identifier: String
  init(identifier: String) { self.identifier = identifier }
}
final class BGContinuedProcessingTaskRequest: BGTaskRequest {
  enum Strategy { case fail, queue }
  var strategy = Strategy.queue
  init(identifier: String, title: String, subtitle: String) { super.init(identifier: identifier) }
}
final class BGProcessingTaskRequest: BGTaskRequest {
  var requiresNetworkConnectivity = false
  var requiresExternalPower = false
}
final class BGTaskScheduler {
  static let shared = BGTaskScheduler()
  var registrations: [String] = []
  var registrationSucceeds = true
  var handler: ((BGTask) -> Void)?
  var requests: [BGTaskRequest] = []
  var submissions: [String: (Error?) -> Void] = [:]
  var cancellations: [String] = []
  func register(forTaskWithIdentifier identifier: String, using queue: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool {
    registrations.append(identifier)
    if registrationSucceeds { handler = launchHandler }
    return registrationSucceeds
  }
  func submitTaskRequest(_ request: BGTaskRequest, completionHandler: @escaping (Error?) -> Void) {
    requests.append(request); submissions[request.identifier] = completionHandler
  }
  func submit(_ request: BGTaskRequest) throws { requests.append(request) }
  func cancel(taskRequestWithIdentifier id: String) { cancellations.append(id) }
  func resolve(_ id: String, error: Error?) { submissions.removeValue(forKey: id)?(error) }
  func deliver(_ id: String) -> BGContinuedProcessingTask {
    let task = BGContinuedProcessingTask(id)
    handler?(task)
    return task
  }
}
@MainActor final class BackgroundActivity {
  static var all: [BackgroundActivity] = []
  var ended = false
  var expiration: (@MainActor () -> Void)?
  init(name: String, onExpiration: (@MainActor () -> Void)?) { expiration = onExpiration; Self.all.append(self) }
  func end() { ended = true }
  func expire() { end(); expiration?() }
}
enum MemoraModel { static let backgroundSummaryTaskID = "app.memora.fixture.processing" }
