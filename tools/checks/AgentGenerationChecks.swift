import Foundation

@main
struct AgentGenerationChecks {
  @MainActor
  static func main() async throws {
    for provider in LLMProvider.allCases {
      precondition(AgentGenerationPolicy.resolve(provider: provider, modelID: provider.defaultModelID, hasCustomEndpoint: true) == nil)
    }
    for model in ["gpt-6-sol", "gpt-6-luna", "gpt-6-astra"] {
      let policy = AgentGenerationPolicy.resolve(provider: .openAI, modelID: model, hasCustomEndpoint: false)!
      var body: [String: Any] = ["model": model, "messages": [], "tools": [], "stream_options": ["include_obfuscation": false]]
      policy.apply(to: &body, allowance: 1234, isStreaming: true)
      precondition(body["max_completion_tokens"] as? Int == 1234 && body["max_tokens"] == nil)
      let options = body["stream_options"] as! [String: Any]
      precondition(options["include_usage"] as? Bool == true && options["include_obfuscation"] as? Bool == false)
      body = ["model": model]
      policy.apply(to: &body, allowance: 32_000, isStreaming: false)
      precondition(body["stream_options"] == nil)
      precondition(body["reasoning_effort"] == nil)
      body["tools"] = [["type": "function", "function": ["name": "list_tasks"]]]
      policy.apply(to: &body, allowance: 32_000, isStreaming: false)
      if model == "gpt-6-astra" { precondition(body["reasoning_effort"] == nil) }
      else { precondition(body["reasoning_effort"] as? String == "none") }
    }
    for model in ["deepseek-flash", "deepseek-v4-pro"] {
      let policy = AgentGenerationPolicy.resolve(provider: .deepSeek, modelID: model, hasCustomEndpoint: false)!
      var body: [String: Any] = [:]
      policy.apply(to: &body, allowance: 32_000, isStreaming: true)
      precondition(body["max_tokens"] as? Int == 32_000 && body["stream_options"] == nil)
    }
    precondition(AgentGenerationPolicy.resolve(provider: .openAI, modelID: "gpt-6-sol-future", hasCustomEndpoint: false) == nil)
    precondition(AgentGenerationPolicy.resolve(provider: .deepSeek, modelID: "memora-standard", hasCustomEndpoint: false) == nil)
    for provider: LLMProvider in [.google, .moonshot, .xAI, .mistral, .qwen, .openRouter] {
      precondition(AgentGenerationPolicy.resolve(provider: provider, modelID: provider.defaultModelID, hasCustomEndpoint: false) == nil)
    }

    var budget = AgentOutputBudget()
    for _ in 0..<16 {
      let limit = try budget.reserve(maximum: 32_000)
      precondition(limit.maximumTokens == 32_000)
      try budget.settle(limit, reportedOutputTokens: 1_000)
    }
    precondition(budget.chargedTokens == 16_000)
    budget = AgentOutputBudget()
    for _ in 0..<4 {
      let ticket = try budget.reserve(maximum: 32_000)
      try budget.settle(ticket, reportedOutputTokens: nil)
    }
    precondition(budget.chargedTokens == 128_000)
    rejects { _ = try budget.reserve(maximum: 1) }
    budget = AgentOutputBudget()
    rejects { _ = try budget.reserve(maximum: 0) }
    rejects { _ = try budget.reserve(maximum: -1) }
    let missing = AgentOutputBudget.Reservation(id: UUID(), maximumTokens: 1)
    rejects { try budget.settle(missing, reportedOutputTokens: 0) }
    let first = try budget.reserve(maximum: 32_000)
    let second = try budget.reserve(maximum: 32_000)
    precondition(budget.chargedTokens == 64_000)
    try budget.settle(second, reportedOutputTokens: 1_000)
    try budget.settle(first, reportedOutputTokens: -1)
    precondition(budget.chargedTokens == 33_000)
    rejects { try budget.settle(first, reportedOutputTokens: 0) }
    budget = AgentOutputBudget()
    for _ in 0..<4 {
      let ticket = try budget.reserve(maximum: 32_000)
      try budget.settle(ticket, reportedOutputTokens: 31_500)
    }
    let remaining = try budget.reserve(maximum: 32_000)
    precondition(remaining.maximumTokens == 2_000)
    try budget.settle(remaining, reportedOutputTokens: 2_000)
    rejects { _ = try budget.reserve(maximum: 1) }
    budget = AgentOutputBudget()
    let invalid = try budget.reserve(maximum: 1)
    rejects { try budget.settle(invalid, reportedOutputTokens: Int.max) }
    rejects { _ = try budget.reserve(maximum: 1) }
    budget = AgentOutputBudget()
    let huge = try budget.reserve(maximum: Int.max)
    precondition(huge.maximumTokens == 128_000)

    for count in [0, 57, 32_000] {
      let usage = CloudTokenUsage(response: ["usage": ["completion_tokens": count, "completion_tokens_details": ["reasoning_tokens": count]]], usesAnthropicAPI: false)
      precondition(usage.outputTokens == count)
      precondition(CloudTokenUsage(response: ["usage": ["output_tokens": count]], usesAnthropicAPI: true).outputTokens == count)
    }
    for value: Any in [true, false, -1, 0.5, "12", NSNull(), Double.infinity, NSNumber(value: UInt64.max)] {
      precondition(CloudTokenUsage(response: ["usage": ["completion_tokens": value]], usesAnthropicAPI: false).outputTokens == nil)
    }
    precondition(CloudTokenUsage(response: [:], usesAnthropicAPI: false).outputTokens == nil)
    precondition(CloudTokenUsage(response: ["usage": ["total_tokens": 100]], usesAnthropicAPI: false).outputTokens == nil)
    budget = AgentOutputBudget()
    var dispatches = 0
    var executions = 0
    var accepted = 0
    let result = await AgentConversationLoop.run(isAuthorized: { true }, next: {
      let ticket = try budget.reserve(maximum: 32_000)
      dispatches += 1
      try budget.settle(ticket, reportedOutputTokens: nil)
      return AgentTurn(text: "", toolCalls: [AgentToolCall(id: "call\(dispatches)", name: "list_tasks", arguments: [:])])
    }, execute: { _ in
      executions += 1
      return AgentToolOutcome(text: "synthetic")
    }, accept: { _, _ in accepted += 1 })
    precondition(result.failure == .executionLimit && dispatches == 4 && executions == 4 && accepted == 4)
    // A provider that ignored the negotiated cap cannot hand tools to the runner.
    budget = AgentOutputBudget()
    executions = 0
    let overLimit = await AgentConversationLoop.run(isAuthorized: { true }, next: {
      let ticket = try budget.reserve(maximum: 32_000)
      try budget.settle(ticket, reportedOutputTokens: 32_001)
      return AgentTurn(text: "", toolCalls: [AgentToolCall(id: "must-not-run", name: "list_tasks", arguments: [:])])
    }, execute: { _ in executions += 1; return AgentToolOutcome(text: "must-not-run") }, accept: { _, _ in preconditionFailure("Over-limit turn accepted") })
    precondition(overLimit.failure == .executionLimit && executions == 0)
    print("AgentGenerationChecks: passed (reviewed models only, custom/unknown compatibility, Sol/Luna tool parameters, streaming usage opt-in, 128k reservations, missing usage, refunds, remaining clamp, overflow/malformed counters, real loop stops before fifth dispatch or over-limit tools; no API/keys)")
  }

  static func rejects(_ action: () throws -> Void) {
    do { try action(); preconditionFailure("Output budget admitted an unsafe reservation") }
    catch let failure as AIAnswerFailure { precondition(failure == .executionLimit) }
    catch { preconditionFailure("Unexpected budget error") }
  }
}
