import Foundation
import Synchronization

@main enum SummaryRequestAdmissionChecks {
  static let key = String(repeating: "a", count: 64)
  static let otherKey = String(repeating: "b", count: 64)

  static func main() async throws {
    let instant = ContinuousClock.now
    let clock = Mutex(instant)
    let queue = SummaryRequestAdmission(now: { clock.withLock { $0 } })
    let first = try await queue.acquire(scope: key, maximumConcurrent: 2)
    let second = try await queue.acquire(scope: key, maximumConcurrent: 2)
    let strict = Task { try await queue.acquire(scope: key, maximumConcurrent: 1) }
    await wait(queue, waiting: 1)
    let later = Task { try await queue.acquire(scope: key, maximumConcurrent: 2) }
    await wait(queue, waiting: 2)
    let other = try await queue.acquire(scope: otherKey, maximumConcurrent: 2)
    await queue.release(first)
    let held = await queue.counts
    precondition(held.active == 2 && held.waiting == 2, "Strict FIFO request was bypassed")
    await queue.release(second)
    let strictPermit = try await strict.value
    await wait(queue, waiting: 1)
    await queue.release(strictPermit)
    let laterPermit = try await later.value
    await queue.release(laterPermit)
    await queue.release(other)

    let blocker = try await queue.acquire(scope: key, maximumConcurrent: 1)
    let cancelled = Task { try await queue.acquire(scope: key, maximumConcurrent: 2) }
    await wait(queue, waiting: 1)
    cancelled.cancel()
    do { _ = try await cancelled.value; preconditionFailure("Cancelled queue entry admitted") }
    catch is CancellationError {}
    await wait(queue, waiting: 0)
    await queue.release(blocker)

    let sending = try await queue.acquire(scope: key, maximumConcurrent: 2)
    let inFlight = try await queue.acquire(scope: key, maximumConcurrent: 2)
    let rejected = Task { try await queue.acquire(scope: key, maximumConcurrent: 2) }
    await wait(queue, waiting: 1)
    await queue.rateLimited(sending, retryAfter: "120")
    do { _ = try await rejected.value; preconditionFailure("429 automatically retried queued request") }
    catch AIAnswerFailure.rateLimited {}
    await queue.release(sending)
    await queue.release(inFlight)
    clock.withLock { $0 = instant.advanced(by: .seconds(61)) }
    do { _ = try await queue.acquire(scope: key, maximumConcurrent: 2); preconditionFailure("Ignored Retry-After") }
    catch AIAnswerFailure.rateLimited {}
    let independent = try await queue.acquire(scope: otherKey, maximumConcurrent: 2)
    await queue.release(independent)
    clock.withLock { $0 = instant.advanced(by: .seconds(121)) }
    let recovered = try await queue.acquire(scope: key, maximumConcurrent: 2)
    let conservative = Task { try await queue.acquire(scope: key, maximumConcurrent: 2) }
    await wait(queue, waiting: 1)
    await queue.release(recovered)
    let recoveredSecond = try await conservative.value
    await queue.release(recoveredSecond)
    clock.withLock { $0 = instant.advanced(by: .seconds(301)) }
    let one = try await queue.acquire(scope: key, maximumConcurrent: 2)
    let two = try await queue.acquire(scope: key, maximumConcurrent: 2)
    await queue.release(one); await queue.release(two)
    let empty = await queue.counts
    precondition(empty.active == 0 && empty.waiting == 0 && empty.scopes == 0)

    let date = Date(timeIntervalSince1970: 784_111_777)
    for value in ["Sun, 06 Nov 1994 08:49:37 GMT", "Sunday, 06-Nov-94 08:49:37 GMT", "Sun Nov  6 08:49:37 1994"] {
      precondition(SummaryRetryDelay.parse(value, date: date.addingTimeInterval(-120)) == .seconds(120), value)
    }
    precondition(SummaryRetryDelay.parse("0", date: date) == .seconds(0))
    precondition(SummaryRetryDelay.parse(nil, date: date) == .seconds(60))
    precondition(SummaryRetryDelay.parse("-1", date: date) == .seconds(60))
    precondition(SummaryRetryDelay.parse("1.5", date: date) == .seconds(60))
    precondition(SummaryRetryDelay.parse(String(repeating: "9", count: 500), date: date) == .untilRestart)
    precondition(SummaryRetryDelay.parse("Sun, 06 Nov 1994 08:49:37 GMT", date: date.addingTimeInterval(1)) == .seconds(0))

    let full = try await queue.acquire(scope: key, maximumConcurrent: 0)
    let waiting = (0..<16).map { _ in Task { try await queue.acquire(scope: key, maximumConcurrent: 2) } }
    await wait(queue, waiting: 16)
    do { _ = try await queue.acquire(scope: key, maximumConcurrent: 2); preconditionFailure("Queue bound exceeded") }
    catch AIAnswerFailure.executionLimit {}
    for task in waiting { task.cancel() }
    for task in waiting {
      do { _ = try await task.value; preconditionFailure("Cancelled bounded queue entry sent") }
      catch is CancellationError {}
    }
    await queue.release(full)
    let preCancelled = Task {
      while !Task.isCancelled { await Task.yield() }
      return try await queue.acquire(scope: key, maximumConcurrent: 1)
    }
    preCancelled.cancel()
    do { _ = try await preCancelled.value; preconditionFailure("Pre-cancelled task admitted") }
    catch is CancellationError {}

    var permits: [SummaryRequestAdmission.Permit] = []
    for number in 0..<64 { permits.append(try await queue.acquire(scope: String(format: "%064x", number), maximumConcurrent: 1)) }
    do { _ = try await queue.acquire(scope: String(repeating: "c", count: 64), maximumConcurrent: 1); preconditionFailure("Scope bound exceeded") }
    catch AIAnswerFailure.executionLimit {}
    for permit in permits { await queue.release(permit) }
    let expiring = SummaryRequestAdmission(waitTimeout: .milliseconds(20))
    let busy = try await expiring.acquire(scope: key, maximumConcurrent: 1)
    do { _ = try await expiring.acquire(scope: key, maximumConcurrent: 1); preconditionFailure("Queue deadline ignored") }
    catch AIAnswerFailure.executionLimit {}
    await expiring.release(busy)
    let expiredCounts = await expiring.counts
    precondition(expiredCounts.active == 0 && expiredCounts.waiting == 0)
    print("SummaryRequestAdmissionChecks: PASS; cross-job bound, strict FIFO, cancellation, credential isolation, 429 fail-stop, Retry-After seconds/all HTTP date formats, cooldown and recovery with virtual time, bounded scopes. No network or model.")
  }

  static func wait(_ queue: SummaryRequestAdmission, waiting expected: Int) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while await queue.counts.waiting != expected {
      precondition(ContinuousClock.now < deadline, "Queue did not reach expected state")
      await Task.yield()
    }
  }
}
