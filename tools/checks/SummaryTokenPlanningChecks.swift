import Foundation

@main enum SummaryTokenPlanningChecks {
  static func main() {
    var capabilities = ModelCapabilities.conservative(provider: .openAI, modelID: "fixture")
    capabilities.contextWindowTokens = 10_000
    capabilities.source = .userOverride
    let budget = SummaryTokenBudget(capabilities: capabilities, outputReservation: 2_000, instructionText: "指示")!
    precondition(budget.contextTokens == 10_000 && budget.sourceCapacity == 5_946)
    precondition(budget.usesReviewedContext)
    precondition(SummaryTokenBudget(capabilities: .conservative(provider: .openAI, modelID: "unknown"), outputReservation: 2_000, instructionText: "指示")?.usesReviewedContext == false)
    precondition(SummaryTokenBudget(capabilities: capabilities, outputReservation: 2_000, instructionText: String(repeating: "原文", count: 2000)) == nil)
    let raw = (0..<40).map { i in
      "  議題\(i)：API_KEY_Aとapi_key_aは別です。利益は-30万円。11月20日ではなく11月27日。\n訂正を保持します。👨‍👩‍👧‍👦  "
    }.joined()
    let units = [SummarySourceIndex.Unit(prefix: "[00:00] S1 A1: ", text: raw),
                 .init(prefix: "[30:00] S2 A2: ", text: "前半の決定は撤回しました。", beginsBoundary: true)]
    guard case .success(let parts) = SummaryInputPartition.make(units, capacity: 600) else { preconditionFailure() }
    precondition(parts.count > 1)
    precondition(parts.allSatisfy { $0.reduce(0) { $0 + $1.utf8.count + 1 } <= 600 })
    let reconstructed = parts.flatMap { $0 }.filter { $0.hasPrefix(units[0].prefix) }
      .map { String($0.dropFirst(units[0].prefix.count)) }.joined()
    precondition(reconstructed == raw, "Source was truncated or modified at a split")
    precondition(parts.last?.last == units.last?.line)
    guard case .success(let one) = SummaryInputPartition.make(units, capacity: 100_000) else { preconditionFailure() }
    precondition(one == [units.map(\.line)])
    guard case .failure(.contextTooLarge) = SummaryInputPartition.make(units, capacity: 1) else { preconditionFailure() }
    let many = (0..<514).map { _ in SummarySourceIndex.Unit(prefix: "S: ", text: "original") }
    guard case .failure(.executionLimit) = SummaryInputPartition.make(many, capacity: 12) else { preconditionFailure() }
    print("SummaryTokenPlanningChecks: PASS; prompt/output reserve, unknown context, full single pass, ordered lossless Unicode/utterance splits, root evidence IDs, size and request-count guards")
  }
}
