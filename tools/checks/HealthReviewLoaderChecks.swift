import Foundation

@main
struct HealthReviewLoaderChecks {
  @MainActor
  static func main() async {
    let now = Date(timeIntervalSince1970: 10_000)
    let day = ReviewPeriod(start: now.addingTimeInterval(-100), end: now.addingTimeInterval(100))
    let previous = ReviewPeriod(start: now.addingTimeInterval(-200), end: day.start)
    let known = HealthReviewSnapshot(steps: 0, sleepSeconds: 300, workoutSeconds: nil, workoutRecordCount: 0)
    var readPeriod: ReviewPeriod?
    var authorizations = 0
    var shouldFail = false
    let loader = HealthReviewLoader(read: { period in
      readPeriod = period
      if shouldFail { throw NSError(domain: "Checks", code: 1) }
      return known
    }, authorize: { authorizations += 1 })
    await loader.load(day, now: now)
    precondition(loader.snapshot?.steps == 0 && loader.snapshot?.hasData == true)
    precondition(readPeriod?.end == now && loader.updatedAt != nil && !loader.isLoading)
    precondition(authorizations == 0)
    shouldFail = true
    let savedDate = loader.updatedAt
    await loader.load(day, requestsAccess: true, now: now)
    precondition(loader.snapshot?.steps == 0 && loader.updatedAt == savedDate)
    precondition(loader.errorMessage != nil && !loader.isLoading && authorizations == 1)
    await loader.load(previous, now: now)
    precondition(loader.snapshot == nil && loader.updatedAt == nil && loader.errorMessage != nil)
    await loader.load(ReviewPeriod(start: now, end: day.end), requestsAccess: true, now: now)
    precondition(loader.snapshot == nil && loader.errorMessage == nil && !loader.isLoading)
    precondition(authorizations == 1)
    precondition(!HealthReviewSnapshot(steps: nil, sleepSeconds: nil, workoutSeconds: nil, workoutRecordCount: 0).hasData)
    for steps in [Double.nan, .infinity, -1, Double(Int.max)] {
      precondition(HealthReviewSnapshot(steps: steps, sleepSeconds: nil, workoutSeconds: nil, workoutRecordCount: 0).stepCount == nil)
    }
    for seconds in [Double.nan, .infinity, -1, Double(Int.max)] {
      let invalid = HealthReviewSnapshot(steps: 0, sleepSeconds: seconds, workoutSeconds: seconds, workoutRecordCount: 0)
      precondition(invalid.sleepDuration == nil && invalid.workoutDuration == nil)
    }

    var pending: CheckedContinuation<HealthReviewSnapshot, Never>?
    let racing = HealthReviewLoader(read: { period in
      if period == previous {
        return await withCheckedContinuation { pending = $0 }
      }
      return known
    }, authorize: {})
    let old = Task { await racing.load(previous, now: now) }
    while pending == nil { await Task.yield() }
    await racing.load(day, now: now)
    pending?.resume(returning: HealthReviewSnapshot(steps: 999, sleepSeconds: nil, workoutSeconds: nil, workoutRecordCount: 0))
    await old.value
    precondition(racing.period == day && racing.snapshot?.steps == 0 && !racing.isLoading)

    pending = nil
    let cancelled = Task { await racing.load(previous, now: now) }
    while pending == nil { await Task.yield() }
    cancelled.cancel()
    pending?.resume(returning: known)
    await cancelled.value
    precondition(racing.snapshot == nil && !racing.isLoading && racing.errorMessage == nil)

    pending = nil
    let cleared = Task { await racing.load(previous, now: now) }
    while pending == nil { await Task.yield() }
    racing.clear()
    pending?.resume(returning: known)
    await cleared.value
    precondition(racing.snapshot == nil && racing.period == nil && racing.updatedAt == nil)
    precondition(!racing.isLoading && racing.errorMessage == nil)
    print("Health review loader checks passed")
  }
}
