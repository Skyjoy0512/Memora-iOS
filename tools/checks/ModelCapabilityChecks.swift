import Foundation

@main enum ModelCapabilityChecks {
  static func main() {
    precondition(LLMProvider.restored(nil, hasLegacyOpenAIConfiguration: false) == .deepSeek)
    precondition(LLMProvider.restored(nil, hasLegacyOpenAIConfiguration: true) == .openAI)
    for provider in LLMProvider.allCases {
      precondition(LLMProvider.restored(provider.rawValue, hasLegacyOpenAIConfiguration: false) == provider)
      precondition(LLMProvider.restored(provider.rawValue, hasLegacyOpenAIConfiguration: true) == provider)
    }
    for provider in LLMProvider.allCases {
      for id in provider.suggestedModels.map(\.id) + ["unknown-custom", "deepseek-v4-pro"] {
        let official = LLMSelection(provider: provider, modelID: id)
        var custom = official
        custom.endpoint = URL(string: "https://fixture.invalid/v1")!
        let unknown = ModelCapabilityRegistry.capabilities(for: custom, overrides: [:])
        precondition(unknown.source == .conservative && unknown.reasoningControlSupport == .unknown && unknown.promptCachePolicy == .unknown)
        precondition(unknown.requestsPerMinute == nil && unknown.inputPricePerMillionTokens == nil)
        for mode in SummaryProcessingMode.allCases {
          var body: [String: Any] = ["model": id]
          SummaryGenerationPolicy.apply(mode, llm: custom, to: &body)
          precondition(body.count == 1, "Provider flags escaped into custom endpoint")
        }
        let capabilities = ModelCapabilityRegistry.capabilities(for: official, overrides: [:])
        if capabilities.isVerified { precondition(capabilities.reviewURL != nil) }
        if provider != .deepSeek { precondition(!SummaryGenerationPolicy.supportsThinkingControl(official)) }
      }
    }
    let known = LLMSelection(provider: .deepSeek, modelID: "deepseek-v4-pro")
    var original: [String: Any] = ["model": known.modelID]
    SummaryGenerationPolicy.apply(.balanced, llm: known, to: &original)
    precondition(original.count == 1)
    let key = ModelCapabilityOverrides.key(provider: known.provider, modelID: known.modelID)
    let adjusted = ModelCapabilityRegistry.capabilities(for: known,
      overrides: [key: ModelCapabilityOverride(contextWindowTokens: 80_000, maximumOutputTokens: 16_000)])
    precondition(adjusted.contextWindowTokens == 80_000 && adjusted.source == .userOverride)
    precondition(SummaryGenerationPolicy.parallelism(capabilities: ModelCapabilityRegistry.capabilities(for: known), lowPower: false, thermalState: 0) == 2)
    precondition(SummaryGenerationPolicy.parallelism(capabilities: ModelCapabilityRegistry.capabilities(for: known), lowPower: true, thermalState: 0) == 1)
    precondition(SummaryGenerationPolicy.parallelism(capabilities: ModelCapabilityRegistry.capabilities(for: known), lowPower: false, thermalState: 2) == 1)
    precondition(SummaryGenerationPolicy.parallelism(capabilities: .conservative(provider: .openAI, modelID: "unknown"), lowPower: false, thermalState: 0) == 1)
    print("ModelCapabilityChecks: PASS; exact reviewed IDs, unknown providers/models/endpoints, preserved defaults and user overrides")
  }
}
