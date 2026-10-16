import Foundation

/// Only reviewed provider/model contracts receive new request parameters.
/// Custom endpoints and other registered models retain their existing shape.
struct AgentGenerationPolicy {
  enum LimitField: String { case tokens = "max_tokens", completionTokens = "max_completion_tokens" }
  var field: LimitField
  var maximumOutputTokens = 32_000
  var requestsStreamingUsage = false
  var requiresNonReasoningTools = false

  static func resolve(provider: LLMProvider, modelID: String, hasCustomEndpoint: Bool) -> Self? {
    guard !hasCustomEndpoint else { return nil }
    switch provider {
    case .anthropic:
      return Self(field: .tokens)
    case .openAI where ["gpt-6-sol", "gpt-6-luna"].contains(modelID):
      return Self(field: .completionTokens, requestsStreamingUsage: true, requiresNonReasoningTools: true)
    case .openAI where modelID == "gpt-6-astra":
      return Self(field: .completionTokens, requestsStreamingUsage: true)
    case .deepSeek where ["deepseek-flash", "deepseek-v4-pro"].contains(modelID):
      return Self(field: .tokens)
    default:
      return nil
    }
  }

  func apply(to body: inout [String: Any], allowance: Int, isStreaming: Bool) {
    body[field.rawValue] = allowance
    if requiresNonReasoningTools, let tools = body["tools"] as? [Any], !tools.isEmpty {
      body["reasoning_effort"] = "none"
    }
    if isStreaming, requestsStreamingUsage {
      var options = body["stream_options"] as? [String: Any] ?? [:]
      options["include_usage"] = true
      body["stream_options"] = options
    }
  }
}
