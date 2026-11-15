import Foundation

/// What a model can accept, kept separate from what the app happens to send.
/// A capability is only as trustworthy as its `source`: an entry the app declares
/// is not a provider-verified contract, and an unknown model gets the
/// conservative profile rather than a guess borrowed from a similar name.
struct ModelCapabilities: Hashable, Sendable {
  enum Source: String, Codable, Sendable {
    /// Declared by this build for an exact model ID.
    case declared
    /// Confirmed from the provider's own API or documentation.
    case providerAPI
    /// Adjusted by the person for a custom endpoint or a changed model.
    case userOverride
    /// The safe floor for a model whose window is unknown.
    case conservative
  }

  var provider: LLMProvider
  var modelID: String
  var contextWindowTokens: Int
  var maximumOutputTokens: Int
  var supportsToolCalling: Bool
  var supportsReasoning: Bool
  var supportsStructuredOutput: Bool
  var supportsVision: Bool
  /// Prices stay nil until they are confirmed; a made-up number is worse than
  /// showing that the cost is unknown.
  var inputPricePerMillionTokens: Double?
  var outputPricePerMillionTokens: Double?
  var supportsPromptCaching: Bool
  var maximumRequestBytes: Int
  var source: Source
  var verifiedAt: Date?
  var note: String?

  enum Support: String, Hashable, Sendable { case supported, unsupported, unknown }
  enum Cache: String, Hashable, Sendable { case automaticPrefix, explicit, unsupported, unknown }
  var streamingSupport: Support = .unknown
  var structuredOutputSupport: Support = .unknown
  var jsonSchemaSupport: Support = .unknown
  var reasoningControlSupport: Support = .unknown
  var parallelRequestSupport: Support = .unknown
  var usageSupport: Support = .unknown
  var tokenizerSupport: Support = .unknown
  var promptCachePolicy: Cache = .unknown
  var maximumConcurrentRequests: Int?
  var requestsPerMinute: Int?
  var tokensPerMinute: Int?
  var cachedInputPricePerMillionTokens: Double?
  var reviewURL: String?

  var isVerified: Bool { source == .providerAPI && verifiedAt != nil }

  /// The safe floor: a 32K window, 8K output and a 1 MiB request. This is what
  /// an unrecognised model or a custom endpoint receives.
  static func conservative(provider: LLMProvider, modelID: String) -> Self {
    Self(provider: provider, modelID: modelID, contextWindowTokens: 32_768,
      maximumOutputTokens: 8_192, supportsToolCalling: true, supportsReasoning: false,
      supportsStructuredOutput: false, supportsVision: false, inputPricePerMillionTokens: nil,
      outputPricePerMillionTokens: nil, supportsPromptCaching: false,
      maximumRequestBytes: 512 * 1_024, source: .conservative, verifiedAt: nil,
      note: "このモデルの上限は未確認です。安全側の値で動作しています。")
  }

  /// Resolves the profile for one selection. An exact model ID in the catalog
  /// wins; a user override replaces the window and output cap; anything else
  /// is conservative.
  static func resolve(
    provider: LLMProvider,
    modelID: String,
    hasCustomEndpoint: Bool,
    overrides: [String: ModelCapabilityOverride] = ModelCapabilityOverrides.stored()
  ) -> Self {
    let key = ModelCapabilityOverrides.key(provider: provider, modelID: modelID)
    if let override = overrides[key], let applied = override.applying(to: base(provider: provider, modelID: modelID, hasCustomEndpoint: hasCustomEndpoint)) {
      return applied
    }
    return base(provider: provider, modelID: modelID, hasCustomEndpoint: hasCustomEndpoint)
  }

  static func resolve(llm: LLMSelection, overrides: [String: ModelCapabilityOverride] = ModelCapabilityOverrides.stored()) -> Self {
    resolve(provider: llm.provider, modelID: llm.modelID,
      hasCustomEndpoint: llm.endpoint != nil || llm.credentialAccount != nil, overrides: overrides)
  }

  private static func base(provider: LLMProvider, modelID: String, hasCustomEndpoint: Bool) -> Self {
    guard !hasCustomEndpoint else { return .conservative(provider: provider, modelID: modelID) }
    return ModelCapabilityCatalog.declared[entryKey(provider: provider, modelID: modelID)]
      ?? .conservative(provider: provider, modelID: modelID)
  }

  static func entryKey(provider: LLMProvider, modelID: String) -> String {
    "\(provider.rawValue):\(modelID)"
  }
}

/// Exact model IDs this build declares. Entries are deliberately conservative
/// and carry no price until the provider's own documentation confirms one.
enum ModelCapabilityCatalog {
  static let declared: [String: ModelCapabilities] = {
    let specs: [(LLMProvider, String, Int, Int, Bool, Bool, Bool)] = [
      // provider, model, context, max output, tools, reasoning, vision
      (.anthropic, "claude-opus-5", 200_000, 32_000, true, true, true),
      (.anthropic, "claude-sonnet-5", 200_000, 32_000, true, true, true),
      (.anthropic, "claude-haiku-4-5", 200_000, 16_000, true, true, true),
      (.anthropic, "claude-fable-5-1", 200_000, 32_000, true, true, true),
      (.openAI, "gpt-6-sol", 128_000, 32_000, true, true, true),
      (.openAI, "gpt-6-luna", 128_000, 16_000, true, true, true),
      (.openAI, "gpt-6-astra", 200_000, 32_000, true, true, true),
      (.google, "gemini-3.8-flash", 1_000_000, 32_000, true, true, true),
      (.google, "gemini-3.1-pro", 1_000_000, 32_000, true, true, true),
      (.google, "gemini-3.5-flash-lite", 1_000_000, 16_000, true, false, true),
      (.deepSeek, "deepseek-flash", 128_000, 32_000, true, true, false),
      (.deepSeek, "deepseek-v4-pro", 128_000, 32_000, true, true, false),
      (.moonshot, "kimi-k2.6", 256_000, 32_000, true, true, false),
      (.moonshot, "kimi-k3", 256_000, 32_000, true, true, false),
      (.xAI, "grok-4.7", 256_000, 32_000, true, true, true),
      (.mistral, "mistral-medium-latest", 128_000, 16_000, true, false, false),
      (.mistral, "mistral-large-latest", 128_000, 16_000, true, false, false),
      (.mistral, "mistral-small-latest", 128_000, 16_000, true, false, false),
      (.qwen, "qwen-plus", 128_000, 16_000, true, true, false),
      (.qwen, "qwen3-max", 128_000, 32_000, true, true, false),
      (.qwen, "qwen-flash", 128_000, 16_000, true, false, false)
    ]
    var result: [String: ModelCapabilities] = [:]
    for spec in specs {
      result[ModelCapabilities.entryKey(provider: spec.0, modelID: spec.1)] = ModelCapabilities(
        provider: spec.0, modelID: spec.1, contextWindowTokens: spec.2,
        maximumOutputTokens: spec.3, supportsToolCalling: spec.4,
        supportsReasoning: spec.5, supportsStructuredOutput: spec.4,
        supportsVision: spec.6, inputPricePerMillionTokens: nil,
        outputPricePerMillionTokens: nil, supportsPromptCaching: spec.0 == .anthropic,
        maximumRequestBytes: min(4 * 1_048_576, max(1_048_576, spec.2 * 4)),
        source: .declared, verifiedAt: nil,
        note: "アプリが宣言した保守的な上限です。提供元APIでの確認は未実施です。")
    }
    // Documentation-reviewed exact IDs share the catalog used by Ask AI and
    // summaries. Older aliases keep their declared conservative contracts.
    let reviewed: [(LLMProvider, [String], Int, Int, ModelCapabilities.Cache, String)] = [
      (.deepSeek, ["deepseek-flash", "deepseek-v4-pro"], 1_000_000, 393_216, .automaticPrefix,
        "https://api-docs.deepseek.com/quick_start/pricing/"),
      (.openAI, ["gpt-6-sol", "gpt-6-luna", "gpt-6-astra"], 1_050_000, 128_000, .automaticPrefix,
        "https://developers.openai.com/api/docs/models/"),
      (.anthropic, ["claude-fable-5-2", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"],
        1_000_000, 128_000, .explicit, "https://platform.claude.com/docs/en/models/overview")
    ]
    for (provider, ids, context, output, cache, source) in reviewed {
      for id in ids {
        let key = ModelCapabilities.entryKey(provider: provider, modelID: id)
        var entry = result[key] ?? .conservative(provider: provider, modelID: id)
        entry.contextWindowTokens = context
        entry.maximumOutputTokens = output
        entry.maximumRequestBytes = 4 * 1_048_576
        entry.source = .providerAPI
        entry.verifiedAt = Date(timeIntervalSince1970: 1_794_614_400)
        entry.reviewURL = source + (provider == .openAI ? id : "")
        entry.note = "容量・記載能力を2026-11-14に公式資料で確認。実API・アカウント制限・価格は未検証です。"
        entry.streamingSupport = .supported
        entry.parallelRequestSupport = .supported
        entry.usageSupport = .supported
        entry.promptCachePolicy = cache
        entry.supportsPromptCaching = true
        if provider == .anthropic {
          entry.supportsToolCalling = true
          entry.supportsReasoning = true
          entry.supportsVision = true
        }
        if provider == .deepSeek {
          entry.supportsVision = id == "deepseek-flash"
          entry.structuredOutputSupport = .supported
          entry.reasoningControlSupport = .supported
        } else if provider == .openAI {
          entry.structuredOutputSupport = .supported
          entry.jsonSchemaSupport = .supported
        }
        result[key] = entry
      }
    }
    return result
  }()

  static func declared(provider: LLMProvider, modelID: String) -> ModelCapabilities? {
    declared[ModelCapabilities.entryKey(provider: provider, modelID: modelID)]
  }
}

/// A person-set window for a model whose real limits differ, or for a custom
/// endpoint. Only the fields present are replaced.
struct ModelCapabilityOverride: Codable, Hashable, Sendable {
  var contextWindowTokens: Int?
  var maximumOutputTokens: Int?
  var maximumRequestBytes: Int?

  func applying(to base: ModelCapabilities) -> ModelCapabilities? {
    let context = contextWindowTokens.map { max(4_096, min($0, 4_000_000)) } ?? base.contextWindowTokens
    let output = maximumOutputTokens.map { max(256, min($0, 256_000)) } ?? base.maximumOutputTokens
    guard output < context else { return nil }
    let bytes = maximumRequestBytes.map { max(65_536, min($0, 32 * 1_048_576)) } ?? base.maximumRequestBytes
    var result = base
    result.contextWindowTokens = context
    result.maximumOutputTokens = output
    result.maximumRequestBytes = bytes
    result.source = .userOverride
    result.verifiedAt = nil
    result.note = "利用者が設定した上限です。"
    return result
  }
}

enum ModelCapabilityOverrides {
  static let defaultsKey = "ai.modelCapabilities.overrides"

  static func key(provider: LLMProvider, modelID: String) -> String {
    ModelCapabilities.entryKey(provider: provider, modelID: modelID)
  }

  static func stored() -> [String: ModelCapabilityOverride] {
    guard let data = UserDefaults.standard.data(forKey: defaultsKey),
          let decoded = try? JSONDecoder().decode([String: ModelCapabilityOverride].self, from: data) else { return [:] }
    return decoded
  }

  static func save(_ overrides: [String: ModelCapabilityOverride]) {
    guard let data = try? JSONEncoder().encode(overrides) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }
}

