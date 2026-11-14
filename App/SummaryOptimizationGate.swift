import Foundation

/// New paid execution routes require a reviewed benchmark for this contract.
/// An offline checker report alone never installs a route approval.
enum SummaryOptimizationGate {
  static let specification = "plan-parallel-v1"
  private static let reviews: [Review] = []

  static func permitsParallelComposition(input: MeetingSummaryInput, llm: LLMSelection, sourceBytes: Int) -> Bool {
    guard input.preferences.length == .detailed, !input.template.preservesFormat, llm.endpoint == nil,
          !llm.isMemoraIntelligence, ModelCapabilityRegistry.capabilities(for: llm).isVerified,
          SummaryGenerationPolicy.parallelParts(input.preferences.processingMode, llm: llm) > 1 else { return false }
    let profiles = Set(([input.template] + input.automaticCandidates).map(\.id))
    return reviews.contains { review in
      review.specification == specification && review.provider == llm.provider && review.modelID == llm.modelID &&
        !review.humanReviewID.isEmpty && review.evaluationSHA256.count == 64 && review.repeatedRuns >= 3 &&
        review.criticalErrors == 0 && review.qualityRegressions == 0 && review.allOfficialCategoriesReviewed &&
        review.coldAndWarmReviewed && review.concurrencyWidths.contains(SummaryGenerationPolicy.parallelParts(input.preferences.processingMode, llm: llm)) &&
        review.latencyRatio.isFinite && review.latencyRatio > 0 && review.latencyRatio < 1 &&
        review.costRatio.isFinite && review.costRatio >= 0 && review.costRatio <= 1 &&
        review.sourceBytes.contains(sourceBytes) && profiles.isSubset(of: review.profileIDs)
    }
  }

  private struct Review {
    var specification: String
    var provider: LLMProvider
    var modelID: String
    var profileIDs: Set<String>
    var sourceBytes: ClosedRange<Int>
    var evaluationSHA256: String
    var humanReviewID: String
    var repeatedRuns: Int
    var criticalErrors: Int
    var qualityRegressions: Int
    var allOfficialCategoriesReviewed: Bool
    var coldAndWarmReviewed: Bool
    var concurrencyWidths: Set<Int>
    /// Worst reviewed cohort, including cold-cache dispatch and continuations.
    var latencyRatio: Double
    var costRatio: Double
  }
}
