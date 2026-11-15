import Foundation

/// Coordinates AI requests across jobs, without pooling their connections
/// or retaining prompts. A provider rejection never schedules a paid retry.
actor SummaryRequestAdmission {
  static let shared = SummaryRequestAdmission()
  private let now: @Sendable () -> ContinuousClock.Instant
  private let waitTimeout: Duration
  private var scopes: [String: Scope] = [:]
  private let maximumScopes = 64
  private let maximumWaiters = 16

  init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }, waitTimeout: Duration = .seconds(120)) {
    self.now = now
    self.waitTimeout = min(.seconds(120), max(.milliseconds(1), waitTimeout))
  }

  var counts: (active: Int, waiting: Int, scopes: Int) {
    (scopes.values.reduce(0, { $0 + $1.active.count }),
      scopes.values.reduce(0, { $0 + $1.waiters.count }), scopes.count)
  }

  struct Permit: Sendable {
    var id: UUID
    var scope: String
  }

  enum Priority: Int, Sendable { case background, userInitiated, interactive }

  func acquire(scope key: String, maximumConcurrent: Int, priority: Priority = .userInitiated,
               requestsPerMinute: Int? = nil, tokensPerMinute: Int? = nil,
               tokenReservation: Int? = nil) async throws -> Permit {
    try Task.checkCancellation()
    prune()
    guard key.utf8.count == 64, key.allSatisfy({ "0123456789abcdef".contains($0) }),
          scopes[key] != nil || scopes.count < maximumScopes,
          scopes.values.reduce(0, { $0 + $1.waiters.count }) < maximumWaiters else {
      throw AIAnswerFailure.executionLimit
    }
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        var scope = scopes[key] ?? Scope()
        guard !scope.blockedUntilRestart, scope.blockedUntil.map({ $0 <= now() }) ?? true else {
          continuation.resume(throwing: AIAnswerFailure.rateLimited); return
        }
        if let rpm = requestsPerMinute {
          guard (1...1_000_000).contains(rpm) else { continuation.resume(throwing: AIAnswerFailure.executionLimit); return }
          scope.requestsPerMinute = min(scope.requestsPerMinute ?? rpm, rpm)
        }
        if let tpm = tokensPerMinute {
          guard (1...100_000_000).contains(tpm), let tokens = tokenReservation, tokens > 0, tokens <= tpm else {
            continuation.resume(throwing: AIAnswerFailure.executionLimit); return
          }
          scope.tokensPerMinute = min(scope.tokensPerMinute ?? tpm, tpm)
        }
        let timeout = Task {
          do { try await Task.sleep(for: waitTimeout) } catch { return }
          expire(id, scope: key)
        }
        scope.waiters.append(Waiter(id: id, limit: min(4, max(1, maximumConcurrent)), priority: priority, tokens: tokenReservation, continuation: continuation, timeout: timeout))
        scopes[key] = scope
        drain(key)
      }
    } onCancel: {
      Task { await self.cancel(id, scope: key) }
    }
  }

  func release(_ permit: Permit) {
    scopes[permit.scope]?.active.removeValue(forKey: permit.id)
    drain(permit.scope)
    prune()
  }

  func rateLimited(_ permit: Permit, retryAfter: String?, date: Date = Date()) {
    guard var scope = scopes[permit.scope], scope.active[permit.id] != nil else { return }
    switch SummaryRetryDelay.parse(retryAfter, date: date) {
    case .seconds(let seconds):
      let deadline = now().advanced(by: .seconds(seconds))
      scope.blockedUntil = max(scope.blockedUntil ?? deadline, deadline)
    case .untilRestart: scope.blockedUntilRestart = true
    }
    scope.reducedUntil = now().advanced(by: .seconds(300))
    let waiters = scope.waiters
    scope.waiters = []
    scopes[permit.scope] = scope
    for waiter in waiters {
      waiter.timeout.cancel()
      waiter.continuation.resume(throwing: AIAnswerFailure.rateLimited)
    }
  }

  private func cancel(_ id: UUID, scope key: String) {
    guard let index = scopes[key]?.waiters.firstIndex(where: { $0.id == id }),
          let waiter = scopes[key]?.waiters.remove(at: index) else { return }
    waiter.timeout.cancel()
    waiter.continuation.resume(throwing: CancellationError())
    drain(key)
    prune()
  }

  private func expire(_ id: UUID, scope key: String) {
    guard let index = scopes[key]?.waiters.firstIndex(where: { $0.id == id }),
          let waiter = scopes[key]?.waiters.remove(at: index) else { return }
    waiter.continuation.resume(throwing: AIAnswerFailure.executionLimit)
    drain(key)
    prune()
  }

  private func drain(_ key: String) {
    guard var scope = scopes[key] else { return }
    var admitted: [Waiter] = [], refused: [Waiter] = []
    scope.dispatches.removeAll { $0.at.advanced(by: .seconds(60)) <= now() }
    while !scope.waiters.isEmpty {
      // At most three later high-priority admissions can bypass the oldest
      // waiter; continuous interactive traffic cannot starve background work.
      var chosen = 0
      if scope.waiters[0].bypasses < 3 {
        for index in scope.waiters.indices where scope.waiters[index].priority.rawValue > scope.waiters[chosen].priority.rawValue {
          chosen = index
        }
      }
      let next = scope.waiters[chosen]
      let recoveryLimit = scope.reducedUntil.map({ $0 > now() }) == true ? 1 : 4
      let limit = min(recoveryLimit, next.limit, scope.active.values.min() ?? 4)
      guard scope.active.count < limit else { break }
      if let rpm = scope.requestsPerMinute, scope.dispatches.count >= rpm {
        refused.append(scope.waiters.remove(at: chosen)); continue
      }
      if let tpm = scope.tokensPerMinute {
        guard let tokens = next.tokens, tokens <= tpm - scope.dispatches.reduce(0, { $0 + $1.tokens }) else {
          refused.append(scope.waiters.remove(at: chosen)); continue
        }
      }
      guard scope.dispatches.count < 4_096 else { refused.append(scope.waiters.remove(at: chosen)); continue }
      scope.waiters.remove(at: chosen)
      for index in 0..<chosen { scope.waiters[index].bypasses += 1 }
      scope.active[next.id] = next.limit
      scope.dispatches.append(Dispatch(at: now(), tokens: next.tokens ?? 0))
      admitted.append(next)
    }
    scopes[key] = scope
    for waiter in refused {
      waiter.timeout.cancel()
      waiter.continuation.resume(throwing: AIAnswerFailure.rateLimited)
    }
    for waiter in admitted {
      waiter.timeout.cancel()
      waiter.continuation.resume(returning: Permit(id: waiter.id, scope: key))
    }
  }

  private func prune() {
    let instant = now()
    scopes = scopes.filter { _, value in
      !value.active.isEmpty || !value.waiters.isEmpty || value.blockedUntilRestart ||
        value.dispatches.contains(where: { $0.at.advanced(by: .seconds(60)) > instant }) && (value.requestsPerMinute != nil || value.tokensPerMinute != nil) ||
        value.blockedUntil.map({ $0 > instant }) == true || value.reducedUntil.map({ $0 > instant }) == true
    }
  }

  private struct Scope {
    var active: [UUID: Int] = [:]
    var waiters: [Waiter] = []
    var blockedUntil: ContinuousClock.Instant?
    var blockedUntilRestart = false
    var reducedUntil: ContinuousClock.Instant?
    var requestsPerMinute: Int?
    var tokensPerMinute: Int?
    var dispatches: [Dispatch] = []
  }

  private struct Dispatch { var at: ContinuousClock.Instant; var tokens: Int }

  private struct Waiter {
    var id: UUID
    var limit: Int
    var priority: Priority
    var tokens: Int?
    var bypasses = 0
    var continuation: CheckedContinuation<Permit, Error>
    var timeout: Task<Void, Never>
  }
}
