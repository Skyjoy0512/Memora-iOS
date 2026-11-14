import Foundation

/// Explicitly reviewed contracts only. An unknown route is unverified, not
/// assumed incapable; it keeps the original request without speculative flags.
enum SummaryGenerationPolicy {
  static func supportsThinkingControl(_ llm: LLMSelection) -> Bool {
    SummaryProviderAdapter.supportsThinkingControl(llm)
  }

  static func apply(_ mode: SummaryProcessingMode, llm: LLMSelection, to body: inout [String: Any]) {
    SummaryProviderAdapter.apply(mode, llm: llm, to: &body)
  }

  static func parallelParts(_ mode: SummaryProcessingMode, llm: LLMSelection) -> Int {
    parallelism(capabilities: ModelCapabilityRegistry.capabilities(for: llm),
      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
      thermalState: ProcessInfo.processInfo.thermalState.rawValue)
  }
  static func parallelism(capabilities: ModelCapabilities, lowPower: Bool, thermalState: Int) -> Int {
    guard capabilities.parallelRequestSupport == .supported,
          !lowPower, thermalState < 2 else { return 1 }
    // Two workers preserve the call count and reasoning policy. Higher widths
    // are testable in the scheduler, but need real rate/cost evidence to adopt.
    return min(2, max(1, capabilities.requestsPerMinute ?? 2))
  }
}
