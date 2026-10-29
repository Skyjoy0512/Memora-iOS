import Foundation

/// Local byte/request guards are independent of provider billing and never retry a request.
/// A model with a larger verified request size may raise its own ceiling, but
/// the guards stay finite: no request, loop or charge is unbounded.
struct AgentSessionBudget {
  static let maximumRequests = 16
  static let maximumRequestBytes = 512 * 1024
  static let maximumTotalRequestBytes = 4 * 1024 * 1024
  static let maximumResponseBytes = 2 * 1024 * 1024
  static let maximumDuration: Duration = .seconds(600)

  /// The ceilings this run actually uses. The defaults keep the old limits for
  /// a model whose request size is unknown.
  var limitRequests = Self.maximumRequests
  var limitRequestBytes = Self.maximumRequestBytes
  var limitTotalRequestBytes = Self.maximumTotalRequestBytes
  var limitDuration: Duration = Self.maximumDuration

  private(set) var requests = 0
  private(set) var requestBytes = 0
  private(set) var responseBytes = 0
  private var startedAt: ContinuousClock.Instant?

  init() {}

  mutating func reserveRequest(bytes: Int, now: ContinuousClock.Instant = .now) throws {
    guard bytes >= 0, bytes <= limitRequestBytes,
          requestBytes <= limitTotalRequestBytes - bytes,
          requests < limitRequests, hasTime(at: now) else { throw AIAnswerFailure.executionLimit }
    if startedAt == nil { startedAt = now }
    requests += 1
    requestBytes += bytes
  }

  mutating func acceptResponse(bytes: Int, now: ContinuousClock.Instant = .now) throws {
    guard bytes >= 0, bytes <= Self.maximumResponseBytes,
          responseBytes <= Self.maximumResponseBytes - bytes,
          hasTime(at: now) else { throw AIAnswerFailure.executionLimit }
    responseBytes += bytes
  }

  func hasTime(at now: ContinuousClock.Instant = .now) -> Bool {
    startedAt.map { $0.duration(to: now) < limitDuration } ?? true
  }
}
