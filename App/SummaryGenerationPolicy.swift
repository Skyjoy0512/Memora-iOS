import Foundation

/// Explicitly reviewed contracts only. An unknown route is unverified, not
/// assumed incapable; it keeps the original request without speculative flags.
enum SummaryGenerationPolicy {
  static func supportsThinkingControl(_ llm: LLMSelection) -> Bool {
    llm.provider == .deepSeek && llm.endpoint == nil &&
      ["deepseek-flash", "deepseek-v4-pro"].contains(llm.modelID)
  }

  static func apply(_ mode: SummaryProcessingMode, llm: LLMSelection, to body: inout [String: Any]) {
    guard mode != .balanced, supportsThinkingControl(llm) else { return }
    body["thinking"] = ["type": mode == .fast ? "disabled" : "enabled"]
    if mode == .accurate { body["reasoning_effort"] = "high" }
    // Disabling thinking otherwise changes the provider's default ceiling
    // from 64K to 8K. Do not buy speed by introducing length truncation.
    body["max_tokens"] = 65_536
  }

  static func parallelParts(_ mode: SummaryProcessingMode, llm: LLMSelection) -> Int {
    mode == .fast && supportsThinkingControl(llm) ? 2 : 1
  }
}
