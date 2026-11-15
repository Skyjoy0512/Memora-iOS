import Foundation

// The host has no path to the person's keychain, model or credit ledger.
enum KeychainStore { static func string(forKey: String) -> String? { "evaluation-placeholder" } }
enum MemoraCreditMeter { static func observe(_ response: URLResponse) {} }
enum AIEngineService { static func effectiveEngine(_ engine: AIEngine) -> AIEngine { engine } }
enum OnDeviceSummarizer {
  static func summarize(_ input: MeetingSummaryInput, progress: @escaping @MainActor (String) -> Void) async -> Result<MeetingSummary, AIAnswerFailure> { .failure(.noEngine) }
}
