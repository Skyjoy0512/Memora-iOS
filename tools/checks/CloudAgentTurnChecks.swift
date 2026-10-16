import Foundation

@main
struct CloudAgentTurnChecks {
  @MainActor
  static func main() async throws {
    let validCall: [String: Any] = ["id": "call", "type": "function", "function": ["name": "list_tasks", "arguments": "{}"]]
    let turn = try CloudAgentTurnDecoder.chatCompletions(chat([validCall]))
    precondition(turn.toolCalls.count == 1 && turn.toolCalls[0].arguments.isEmpty)
    for value: Any in ["{", "[]", "null", "", NSNull(), ["title": "task"]] {
      var call = validCall
      call["id"] = "other"
      call["function"] = ["name": "create_task", "arguments": value]
      rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([validCall, call])) }
    }
    var missingArguments = validCall
    missingArguments["function"] = ["name": "create_task"]
    rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([missingArguments])) }
    for reason in ["length", "content_filter", "stop", "unknown", ""] {
      rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([validCall], reason: reason)) }
    }
    rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([])) }
    rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([validCall, validCall])) }
    for key in ["id", "type", "function"] {
      var invalid = validCall
      invalid.removeValue(forKey: key)
      rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([validCall, invalid])) }
    }
    for id in ["", " \n", String(repeating: "a", count: 201)] {
      var invalid = validCall
      invalid["id"] = id
      rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat([invalid])) }
    }
    for calls: Any in ["invalid", [1], [NSNull()]] {
      rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat(calls)) }
    }
    let answer: [String: Any] = ["choices": [["finish_reason": "stop", "message": ["content": " 回答 ", "reasoning_content": "理由", "tool_calls": NSNull(), "function_call": NSNull()]]]]
    let text = try CloudAgentTurnDecoder.chatCompletions(answer)
    precondition(text.text == "回答" && text.reasoning == "理由" && text.toolCalls.isEmpty)
    rejects { _ = try CloudAgentTurnDecoder.chatCompletions(["choices": [["message": ["content": "partial"]]]]) }

    let validBlock: [String: Any] = ["type": "tool_use", "id": "call", "name": "list_tasks", "input": [String: Any]()]
    let anthropic = try CloudAgentTurnDecoder.anthropic(claude([validBlock]))
    precondition(anthropic.toolCalls.count == 1 && anthropic.toolCalls[0].arguments.isEmpty)
    for input: Any in ["{}", [], NSNull(), 1] {
      var invalid = validBlock
      invalid["id"] = "other"
      invalid["input"] = input
      rejects { _ = try CloudAgentTurnDecoder.anthropic(claude([validBlock, invalid])) }
    }
    for key in ["id", "name", "input"] {
      var invalid = validBlock
      invalid.removeValue(forKey: key)
      rejects { _ = try CloudAgentTurnDecoder.anthropic(claude([invalid])) }
    }
    for reason in ["max_tokens", "model_context_window_exceeded", "pause_turn", "refusal", "end_turn", "unknown", ""] {
      rejects { _ = try CloudAgentTurnDecoder.anthropic(claude([validBlock], reason: reason)) }
    }
    rejects { _ = try CloudAgentTurnDecoder.anthropic(claude([])) }
    rejects { _ = try CloudAgentTurnDecoder.anthropic(claude([validBlock, validBlock])) }
    let finished = try CloudAgentTurnDecoder.anthropic(claude([["type": "text", "text": "回答"]], reason: "end_turn"))
    precondition(finished.text == "回答" && finished.toolCalls.isEmpty)

    // A valid first call must not escape when a later call fails validation.
    var tooMany = (0..<25).map { index -> [String: Any] in
      var call = validCall; call["id"] = "call\(index)"; return call
    }
    rejects { _ = try CloudAgentTurnDecoder.chatCompletions(chat(tooMany)) }
    tooMany = (0..<25).map { index in var block = validBlock; block["id"] = "call\(index)"; return block }
    rejects { _ = try CloudAgentTurnDecoder.anthropic(claude(tooMany)) }
    var requests = 0
    var executions = 0
    var accepted = 0
    missingArguments["id"] = "other"
    let result = await AgentConversationLoop.run(isAuthorized: { true }, next: {
      requests += 1
      return try CloudAgentTurnDecoder.chatCompletions(chat([validCall, missingArguments]))
    }, execute: { _ in
      executions += 1
      return AgentToolOutcome(text: "must not run")
    }, accept: { _, _ in accepted += 1 })
    precondition(result.failure == .server && requests == 1 && executions == 0 && accepted == 0)
    print("CloudAgentTurnChecks: passed (whole-batch validation, JSON fallback, completion reasons, malformed/missing arguments, IDs, bounds, valid empty object)")
  }

  static func chat(_ calls: Any, reason: String = "tool_calls") -> [String: Any] {
    ["choices": [["finish_reason": reason, "message": ["tool_calls": calls]]]]
  }

  static func claude(_ blocks: [[String: Any]], reason: String = "tool_use") -> [String: Any] {
    ["content": blocks, "stop_reason": reason]
  }

  static func rejects(_ action: () throws -> Void) {
    do { try action(); preconditionFailure("Incomplete provider turn became executable") } catch {}
  }
}
