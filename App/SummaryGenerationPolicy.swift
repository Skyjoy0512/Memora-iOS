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
  static func parallelism(capabilities: ModelCapabilities, lowPower: Bool, thermalState: Int, memoryHeadroomBytes: UInt64? = nil) -> Int {
    guard capabilities.parallelRequestSupport == .supported,
          !lowPower, thermalState < 2,
          memoryHeadroomBytes.map({ $0 >= 128 * 1_024 * 1_024 }) ?? true else { return 1 }
    // Account concurrency is not inferred from RPM or a provider name. Unknown
    // contracts retain two; reviewed account limits can admit widths 1...4.
    return min(4, max(1, capabilities.maximumConcurrentRequests ?? 2))
  }
}
