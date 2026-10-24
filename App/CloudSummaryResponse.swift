import Foundation

/// Text completion may request a bounded continuation, but never carries tools.
struct CloudSummaryResponse {
  var text: String
  var wasCutOff: Bool

  init(_ response: [String: Any], provider: CloudStreamAccumulator.Provider) throws {
    guard response["error"] == nil else { throw AIAnswerFailure.server }
    let reason: String?
    let raw: String
    if provider == .anthropic {
      reason = response["stop_reason"] as? String
      guard let blocks = response["content"] as? [[String: Any]],
            blocks.allSatisfy({ ["text", "thinking", "redacted_thinking"].contains($0["type"] as? String ?? "") }),
            blocks.filter({ $0["type"] as? String == "text" }).allSatisfy({ $0["text"] is String }) else {
        throw AIAnswerFailure.server
      }
      raw = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
    } else {
      guard let choices = response["choices"] as? [[String: Any]], choices.count == 1,
            let choice = choices.first, let message = choice["message"] as? [String: Any],
            (message["role"] == nil || message["role"] as? String == "assistant"),
            (message["function_call"] == nil || message["function_call"] is NSNull) else { throw AIAnswerFailure.server }
      if let calls = message["tool_calls"], !(calls is NSNull) {
        guard let calls = calls as? [Any], calls.isEmpty else { throw AIAnswerFailure.server }
      }
      if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw AIAnswerFailure.refused }
      reason = choice["finish_reason"] as? String
      raw = message["content"] as? String ?? ""
    }
    if reason == "refusal" || reason == "content_filter" { throw AIAnswerFailure.refused }
    if ["pause_turn", "model_context_window_exceeded"].contains(reason ?? "") { throw AIAnswerFailure.executionLimit }
    guard let reason else { throw AIAnswerFailure.connectionLost }
    let accepted = provider == .anthropic ? ["end_turn", "stop_sequence", "max_tokens"] : ["stop", "length"]
    guard accepted.contains(reason) else { throw AIAnswerFailure.server }
    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIAnswerFailure.empty }
    text = raw
    wasCutOff = reason == "length" || reason == "max_tokens"
  }
}
