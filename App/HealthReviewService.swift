import Foundation
import HealthKit

@MainActor
enum HealthReviewService {
  private static let store = HKHealthStore()

  static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  static func requestAccess() async throws {
    guard isAvailable else { throw HealthReviewError.unavailable }
    let types: Set<HKObjectType> = [
      HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()
    ]
    try await store.requestAuthorization(toShare: [], read: types)
  }

  static func read(_ period: ReviewPeriod) async throws -> HealthReviewSnapshot {
    guard isAvailable else { throw HealthReviewError.unavailable }
    let steps = try await stepTotal(period)
    try Task.checkCancellation()
    let sleepIntervals = try await sleepIntervals(period)
    try Task.checkCancellation()
    let workouts = try await workoutIntervals(period)
    try Task.checkCancellation()
    return HealthReviewSnapshot(
      steps: steps,
      sleepSeconds: sleepIntervals.isEmpty ? nil : HealthReviewSnapshot.mergedDuration(sleepIntervals, within: period),
      workoutSeconds: workouts.isEmpty ? nil : HealthReviewSnapshot.mergedDuration(workouts, within: period),
      workoutRecordCount: workouts.count
    )
  }

  private static func stepTotal(_ period: ReviewPeriod) async throws -> Double? {
    try await withCheckedThrowingContinuation { continuation in
      let predicate = HKQuery.predicateForSamples(withStart: period.start, end: period.end, options: .strictStartDate)
      let query = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count())) }
      }
      store.execute(query)
    }
  }

  private static func sleepIntervals(_ period: ReviewPeriod) async throws -> [DateInterval] {
    try await withCheckedThrowingContinuation { continuation in
      let predicate = HKQuery.predicateForSamples(withStart: period.start, end: period.end)
      let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
        if let error { continuation.resume(throwing: error); return }
        let values = Set([
          HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
          HKCategoryValueSleepAnalysis.asleepCore.rawValue,
          HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
          HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ])
        let intervals = (samples as? [HKCategorySample] ?? []).filter { values.contains($0.value) && $0.endDate > $0.startDate }
          .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        continuation.resume(returning: intervals)
      }
      store.execute(query)
    }
  }

  private static func workoutIntervals(_ period: ReviewPeriod) async throws -> [DateInterval] {
    try await withCheckedThrowingContinuation { continuation in
      let predicate = HKQuery.predicateForSamples(withStart: period.start, end: period.end)
      let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
        if let error { continuation.resume(throwing: error); return }
        let intervals = (samples as? [HKWorkout] ?? []).filter { $0.endDate > $0.startDate }
          .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        continuation.resume(returning: intervals)
      }
      store.execute(query)
    }
  }
}
