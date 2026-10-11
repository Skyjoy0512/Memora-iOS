import Foundation
import Observation

@MainActor
@Observable
final class HealthReviewLoader {
  private(set) var snapshot: HealthReviewSnapshot?
  private(set) var period: ReviewPeriod?
  private(set) var updatedAt: Date?
  private(set) var errorMessage: String?
  private(set) var isLoading = false
  @ObservationIgnored private var requestID = UUID()
  @ObservationIgnored private var read: @MainActor (ReviewPeriod) async throws -> HealthReviewSnapshot
  @ObservationIgnored private var authorize: @MainActor () async throws -> Void

  init(read: @escaping @MainActor (ReviewPeriod) async throws -> HealthReviewSnapshot,
       authorize: @escaping @MainActor () async throws -> Void) {
    self.read = read
    self.authorize = authorize
  }

  func load(_ requestedPeriod: ReviewPeriod, requestsAccess: Bool = false, now: Date = .now) async {
    let identifier = UUID()
    requestID = identifier
    if period != requestedPeriod {
      snapshot = nil
      updatedAt = nil
    }
    period = requestedPeriod
    errorMessage = nil
    isLoading = false
    let readPeriod = ReviewPeriod(start: requestedPeriod.start, end: min(requestedPeriod.end, now))
    guard readPeriod.end > readPeriod.start else { return }
    isLoading = true
    defer { if requestID == identifier { isLoading = false } }
    do {
      try Task.checkCancellation()
      if requestsAccess { try await authorize() }
      try Task.checkCancellation()
      guard requestID == identifier else { return }
      let result = try await read(readPeriod)
      try Task.checkCancellation()
      guard requestID == identifier else { return }
      snapshot = result
      updatedAt = .now
    } catch {
      guard requestID == identifier, !Task.isCancelled, !(error is CancellationError) else { return }
      errorMessage = "健康データを読み込めませんでした。ヘルスケアの許可を確認して、再読み込みしてください。"
    }
  }

  func clear() {
    requestID = UUID()
    snapshot = nil
    period = nil
    updatedAt = nil
    errorMessage = nil
    isLoading = false
  }
}
