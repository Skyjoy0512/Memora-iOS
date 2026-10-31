import Foundation

// Only UIKit/BackgroundTasks are substituted; the scheduler source and execution gate are production code.
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
      precondition(request.strategy == .queue)
      return (job, request.identifier)
    }
    let (job, id) = begin()
    var result: SummaryExecutionGate.Permission?
    let work = Task { result = await scheduler.waitUntilReady(jobID: job) }
    await drain()
    precondition(result == nil)
    BGTaskScheduler.shared.resolve(id, error: nil)
    await drain()
    precondition(result == nil, "submission success started inference before a delivered lease")
    UIApplication.shared.applicationState = .background
    BackgroundActivity.all.last!.expire()
    await drain()
    precondition(result == nil && expirations.isEmpty, "short UIKit expiry cancelled queued work")
    let task = BGTaskScheduler.shared.deliver(id)
    await work.value
    precondition(result == .continued && BackgroundActivity.all.last!.ended)
    scheduler.report(jobID: job, step: "実際の出力を受信")
    precondition(task.progress.completedUnitCount == 1 && task.progress.totalUnitCount == -1)
    let lateExpiration = task.expirationHandler
    scheduler.finish(jobID: job, success: true)
    precondition(task.completions == [true] && task.progress.isFinished)
    lateExpiration?()
    await drain()
    precondition(expirations.isEmpty)

    UIApplication.shared.applicationState = .active
    let (cancelled, oldID) = begin()
    let waiting = Task { await scheduler.waitUntilReady(jobID: cancelled) }
    await drain()
    scheduler.finish(jobID: cancelled, success: false)
    let cancelledPermission = await waiting.value
    precondition(cancelledPermission == .stopped)
    let (replacement, replacementID) = begin()
    precondition(oldID != replacementID)
    let late = BGTaskScheduler.shared.deliver(oldID)
    precondition(late.completions == [false])
    BGTaskScheduler.shared.resolve(oldID, error: NSError(domain: "fixture", code: 1))
    await drain()
    precondition(failures.isEmpty)
    let live = BGTaskScheduler.shared.deliver(replacementID)
    let permission1 = await scheduler.waitUntilReady(jobID: replacement)
    precondition(permission1 == .continued)
    let expiry = live.expirationHandler
    expiry?()
    await drain()
    precondition(expirations == [replacement] && live.completions == [false])
    scheduler.finish(jobID: replacement, success: false)
    precondition(live.completions == [false], "completed one OS task twice")

    let (foregroundFallback, fallbackID) = begin()
    BGTaskScheduler.shared.resolve(fallbackID, error: NSError(domain: "fixture", code: 2))
    await drain()
    let permission2 = await scheduler.waitUntilReady(jobID: foregroundFallback)
    precondition(permission2 == .foreground)
    UIApplication.shared.applicationState = .background
    BackgroundActivity.all.last!.expire()
    precondition(expirations.contains(foregroundFallback))

    UIApplication.shared.applicationState = .active
    let (backgroundRefused, refusedID) = begin()
    UIApplication.shared.applicationState = .background
    BGTaskScheduler.shared.resolve(refusedID, error: NSError(domain: "fixture", code: 3))
    await drain()
    let permission3 = await scheduler.waitUntilReady(jobID: backgroundRefused)
    precondition(permission3 == .stopped)
    scheduler.finish(jobID: backgroundRefused, success: false)
    precondition(failures.count == 2)

    UIApplication.shared.applicationState = .active
    let automatic = UUID()
    let previous = BGTaskScheduler.shared.requests.count
    scheduler.begin(jobID: automatic, requestsContinuedProcessing: false,
      onExpiration: {}, onFailure: { _ in preconditionFailure() })
    let permission4 = await scheduler.waitUntilReady(jobID: automatic)
    precondition(permission4 == .foreground)
    precondition(BGTaskScheduler.shared.requests.count == previous, "automatic job requested a user-only lease")
    scheduler.finish(jobID: automatic, success: false)

    let (firstConcurrent, firstID) = begin()
    let (secondConcurrent, secondID) = begin()
    var firstPermission: SummaryExecutionGate.Permission?
    var secondPermission: SummaryExecutionGate.Permission?
    let firstWork = Task { firstPermission = await scheduler.waitUntilReady(jobID: firstConcurrent) }
    let secondWork = Task { secondPermission = await scheduler.waitUntilReady(jobID: secondConcurrent) }
    await drain()
    _ = BGTaskScheduler.shared.deliver(secondID)
    await secondWork.value
    precondition(firstPermission == nil && secondPermission == .continued)
    scheduler.finish(jobID: secondConcurrent, success: false)
    _ = BGTaskScheduler.shared.deliver(firstID)
    await firstWork.value
    precondition(firstPermission == .continued)
    scheduler.finish(jobID: firstConcurrent, success: false)

    BGTaskScheduler.shared.registrationSucceeds = false
    let unregistered = SystemSummaryBackgroundScheduler(bundleIdentifier: "app.memora.registration-fixture")
    let rejectedJob = UUID()
    var registrationFailure = false
    unregistered.begin(jobID: rejectedJob, requestsContinuedProcessing: true,
      onExpiration: {}, onFailure: { _ in registrationFailure = true })
    let registrationPermission = await unregistered.waitUntilReady(jobID: rejectedJob)
    precondition(registrationFailure && registrationPermission == .foreground)
    unregistered.finish(jobID: rejectedJob, success: false)

    let gate = SummaryExecutionGate()
    let cancelledWait = Task { await gate.wait() }
    await drain()
    cancelledWait.cancel()
    let permission5 = await cancelledWait.value
    precondition(permission5 == .stopped)
    gate.resolve(.stopped)
    gate.resolve(.continued)
    let permission6 = await gate.wait()
    precondition(permission6 == .stopped)
    print("ContinuedSummarySchedulerChecks passed: wildcard registered once, queue, no send before delivery, delayed background grant, short-lease expiry, cancellation, late callbacks, replacement isolation, foreground fallback, background refusal, automatic policy, no duplicate completion; OS APIs are fixtures")
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
