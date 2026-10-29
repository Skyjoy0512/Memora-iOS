import Foundation

@main
enum ModelCapabilitiesChecks {
  static func main() {
    let unknown = ModelCapabilities.resolve(provider: .openAI, modelID: "gpt-6-sol-preview", hasCustomEndpoint: false, overrides: [:])
    precondition(unknown.source == .conservative)
    precondition(unknown.contextWindowTokens == 32_768)
    precondition(!unknown.isVerified)

    let custom = ModelCapabilities.resolve(provider: .deepSeek, modelID: "deepseek-v4-pro", hasCustomEndpoint: true, overrides: [:])
    precondition(custom.source == .conservative)

    let declared = ModelCapabilities.resolve(provider: .deepSeek, modelID: "deepseek-v4-pro", hasCustomEndpoint: false, overrides: [:])
    precondition(declared.source == .declared)
    precondition(declared.contextWindowTokens == 128_000)
    precondition(declared.maximumOutputTokens == 32_000)

    // A similar but different name must not borrow another model's window.
    let similar = ModelCapabilities.resolve(provider: .deepSeek, modelID: "deepseek-v4", hasCustomEndpoint: false, overrides: [:])
    precondition(similar.contextWindowTokens == unknown.contextWindowTokens)

    let overrideKey = ModelCapabilityOverrides.key(provider: .openAI, modelID: "gpt-6-sol")
    let override = ModelCapabilityOverride(contextWindowTokens: 400_000, maximumOutputTokens: 64_000, maximumRequestBytes: nil)
    let applied = ModelCapabilities.resolve(provider: .openAI, modelID: "gpt-6-sol", hasCustomEndpoint: false,
      overrides: [overrideKey: override])
    precondition(applied.source == .userOverride)
    precondition(applied.contextWindowTokens == 400_000)
    precondition(applied.maximumOutputTokens == 64_000)
    let invalid = ModelCapabilityOverride(contextWindowTokens: 8_000, maximumOutputTokens: 64_000, maximumRequestBytes: nil)
    let rejected = ModelCapabilities.resolve(provider: .openAI, modelID: "gpt-6-sol", hasCustomEndpoint: false,
      overrides: [overrideKey: invalid])
    precondition(rejected.source == .declared)

    let small = TokenBudgetManager.budget(capabilities: unknown, task: .presentation)
    precondition(small.inputTokens < unknown.contextWindowTokens)
    precondition(small.outputTokens <= unknown.maximumOutputTokens)
    precondition(small.inputTokens + small.outputTokens + small.safetyTokens <= unknown.contextWindowTokens)

    let large = TokenBudgetManager.budget(capabilities: declared, task: .presentation)
    precondition(large.inputTokens > 64_000)
    precondition(large.inputTokens <= declared.contextWindowTokens)

    let wide = ModelCapabilities(provider: .google, modelID: "gemini-3.1-pro", contextWindowTokens: 1_000_000,
      maximumOutputTokens: 32_000, supportsToolCalling: true, supportsReasoning: true,
      supportsStructuredOutput: true, supportsVision: true, inputPricePerMillionTokens: nil,
      outputPricePerMillionTokens: nil, supportsPromptCaching: false, maximumRequestBytes: 4_194_304,
      source: .declared, verifiedAt: nil, note: nil)
    let research = TokenBudgetManager.budget(capabilities: wide, task: .research)
    precondition(research.inputTokens <= ContextTaskKind.research.inputTokenTarget)
    precondition(research.inputTokens > 500_000)
    precondition(research.estimatedCostUSD == nil)

    let chat = TokenBudgetManager.budget(capabilities: wide, task: .chat)
    precondition(chat.inputTokens == ContextTaskKind.chat.inputTokenTarget)
    precondition(chat.inputTokens < research.inputTokens)

    let japanese = TokenBudgetManager.estimatedTokens("会議の決定事項をまとめます。")
    precondition(japanese >= 12 && japanese <= 24)
    let ascii = TokenBudgetManager.estimatedTokens("the quick brown fox jumps")
    precondition(ascii >= 6 && ascii <= 12)

    precondition(DeepContextPolicy.task(for: "来週のPowerPoint資料を作って") == .presentation)
    precondition(DeepContextPolicy.task(for: "このプロジェクトの経緯を深掘りして") == .deepAnalysis)
    precondition(DeepContextPolicy.task(for: "今日の予定は？") == .agent)
    precondition(DeepContextPolicy.isDeep("競合比較の提案書を作成して"))

    // The request guard grows for a large model but stays finite.
    let session = AgentSessionBudget(capabilities: wide)
    precondition(session.limitRequestBytes > AgentSessionBudget.maximumRequestBytes)
    precondition(session.limitRequestBytes <= 8 * 1024 * 1024)
    let conservativeSession = AgentSessionBudget(capabilities: unknown)
    precondition(conservativeSession.limitRequestBytes == AgentSessionBudget.maximumRequestBytes)

    let output = AgentOutputBudget(maximumTokens: 16_000)
    precondition(output.limitTokens == 16_000)

    print("ModelCapabilitiesChecks: passed (exact-ID lookup, conservative fallback, override validation, token budgets, deep-context routing, finite guards)")
  }
}
