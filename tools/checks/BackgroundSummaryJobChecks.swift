import Foundation

@main
struct BackgroundSummaryJobChecks {
  static func main() throws {
    let llm = LLMSelection(provider: .openAI, modelID: "gpt-test", displayName: "Test")
    let market = SummaryMarketTemplate(id: "custom.one", title: "議事録", detail: "詳細", symbol: .doc,
      lead: "lead", sections: ["決定"], focus: "focus")
    let job = PendingSummaryJob(meetingID: UUID(), choice: .market(market), engineRawValue: AIEngine.cloud.rawValue,
      llm: llm, automaticallySelect: true, useCaseID: "sales", preferences: SummaryPreferences(),
      cloudDisclosureConfirmed: true, usesCloud: true)
    let data = try JSONEncoder().encode(job)
    let restored = try JSONDecoder().decode(PendingSummaryJob.self, from: data)
    precondition(restored.id == job.id && restored.meetingID == job.meetingID)
    precondition(restored.choice == job.choice && restored.engine == .cloud && restored.llm == llm)
    precondition(restored.cloudDisclosureConfirmed && restored.usesCloud && restored.automaticallySelect)
    precondition(restored.preferences == job.preferences && restored.useCaseID == "sales")
    precondition(restored.inputFingerprint == nil && restored.requiresUserRetry == nil)
    var current = job
    current.inputFingerprint = "fixture-fingerprint"
    current.requiresUserRetry = true
    let currentRestored = try JSONDecoder().decode(PendingSummaryJob.self, from: JSONEncoder().encode(current))
    precondition(currentRestored.inputFingerprint == current.inputFingerprint && currentRestored.requiresUserRetry == true)
    print("BackgroundSummaryJobChecks: passed (job codec round-trip)")
  }
}
