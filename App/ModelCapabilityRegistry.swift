import Foundation

/// Shared catalog and user overrides stay authoritative. The facade adds no
/// second model table and never probes a billable API to discover capabilities.
enum ModelCapabilityRegistry {
  static func capabilities(for llm: LLMSelection, overrides: [String: ModelCapabilityOverride] = ModelCapabilityOverrides.stored()) -> ModelCapabilities {
    ModelCapabilities.resolve(llm: llm, overrides: overrides)
  }

  static func outputReservation(for llm: LLMSelection) -> Int {
    if llm.provider == .anthropic { return 16_000 }
    let capability = capabilities(for: llm)
    if llm.provider == .deepSeek, capability.reasoningControlSupport == .supported { return 65_536 }
    if capability.isVerified { return capability.maximumOutputTokens }
    return 16_384
  }
}
