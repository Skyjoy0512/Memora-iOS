import Foundation

/// Optional wire controls live here. Adding planning metadata must not silently
/// change the selected model, provider defaults, reasoning or retention policy.
enum SummaryProviderAdapter {
  static func supportsThinkingControl(_ llm: LLMSelection) -> Bool {
    guard llm.provider == .deepSeek, llm.endpoint == nil, !llm.isMemoraIntelligence else { return false }
    return ModelCapabilities.resolve(provider: llm.provider, modelID: llm.modelID,
      hasCustomEndpoint: false, overrides: [:]).reasoningControlSupport == .supported
  }

  static func apply(_ mode: SummaryProcessingMode, llm: LLMSelection, to body: inout [String: Any]) {
    guard mode != .balanced, supportsThinkingControl(llm) else { return }
    DeepSeek.apply(mode, to: &body)
  }

  private enum DeepSeek {
    static func apply(_ mode: SummaryProcessingMode, to body: inout [String: Any]) {
      // Preserve the pre-existing explicit mode; optimization never selects it.
      body["thinking"] = ["type": mode == .fast ? "disabled" : "enabled"]
      if mode == .accurate { body["reasoning_effort"] = "high" }
      body["max_tokens"] = 65_536
    }
  }
}
