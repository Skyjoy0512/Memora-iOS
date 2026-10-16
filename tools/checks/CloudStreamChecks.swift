import Foundation

@main
struct CloudStreamChecks {
  static func main() throws {
    var openAI = CloudStreamAccumulator(provider: .chatCompletions)
    try openAI.consume(#"{"choices":[{"index":0,"delta":{"content":"こんにちは","reasoning_content":"考え","tool_calls":[{"index":1,"id":"b","type":"function","function":{"name":"list_tasks","arguments":"{"}},{"index":0,"id":"a","type":"function","function":{"name":"read_record","arguments":"{\"id\":"},"extra_content":{"google":{"thought_signature":"signature"}}}]}}]}"#)
    precondition(openAI.text == "こんにちは")
    rejects { _ = try openAI.response() }
    try openAI.consume(#"{"choices":[{"index":0,"delta":{"content":"。","reasoning_content":"中","tool_calls":[{"index":0,"function":{"arguments":"\"record\"}"}},{"index":1,"function":{"arguments":"}"}}]},"finish_reason":"tool_calls"}]}"#)
    try openAI.consume("[DONE]")
    let choices = try openAI.response()["choices"] as! [[String: Any]]
    let message = choices[0]["message"] as! [String: Any]
    let calls = message["tool_calls"] as! [[String: Any]]
    precondition(openAI.text == "こんにちは。" && calls[0]["id"] as? String == "a")
    precondition(message["reasoning_content"] as? String == "考え中")
    precondition(calls[0]["extra_content"] != nil && calls[0]["index"] == nil)

    var claude = CloudStreamAccumulator(provider: .anthropic)
    for payload in [
      #"{"type":"message_start","message":{}}"#,
      #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"思考"}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig"}}"#,
      #"{"type":"content_block_stop","index":0}"#,
      #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool","name":"list_tasks","input":{}}}"#,
      #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{}"}}"#,
      #"{"type":"content_block_stop","index":1}"#,
      #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
      #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"確認します"}}"#,
      #"{"type":"content_block_stop","index":2}"#,
      #"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
      #"{"type":"message_stop"}"#
    ] { try claude.consume(payload) }
    let blocks = try claude.response()["content"] as! [[String: Any]]
    precondition(blocks[0]["signature"] as? String == "sig" && claude.text == "確認します")
    precondition(blocks[1]["input"] is [String: Any])

    for input: Any in ["{}", NSNull(), []] {
      var malformed = CloudStreamAccumulator(provider: .anthropic)
      let start: [String: Any] = ["type": "content_block_start", "index": 0,
        "content_block": ["type": "tool_use", "id": "call", "name": "list_tasks", "input": input]]
      try malformed.consume(String(decoding: JSONSerialization.data(withJSONObject: start), as: UTF8.self))
      try malformed.consume(#"{"type":"content_block_stop","index":0}"#)
      try malformed.consume(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#)
      try malformed.consume(#"{"type":"message_stop"}"#)
      rejects { _ = try malformed.response() }
    }

    var unfinishedInput = CloudStreamAccumulator(provider: .anthropic)
    try unfinishedInput.consume(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"call","name":"create_task","input":{}}}"#)
    try unfinishedInput.consume(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"title\":"}}"#)
    rejects { try unfinishedInput.consume(#"{"type":"content_block_stop","index":0}"#) }

    var truncated = CloudStreamAccumulator(provider: .chatCompletions)
    try truncated.consume(#"{"choices":[{"delta":{"content":"途中"},"finish_reason":"length"}]}"#)
    try truncated.consume("[DONE]")
    rejects { _ = try truncated.response() }
    var invalid = CloudStreamAccumulator(provider: .chatCompletions)
    try invalid.consume(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call","function":{"name":"create_task","arguments":"not-json"}}]},"finish_reason":"tool_calls"}]}"#)
    try invalid.consume("[DONE]")
    rejects { _ = try invalid.response() }
    var unexpected = CloudStreamAccumulator(provider: .anthropic)
    rejects { try unexpected.consume(#"{"type":"message_stop"}"#) }
    var excessive = CloudStreamAccumulator(provider: .chatCompletions)
    rejects { try excessive.consume(String(repeating: "x", count: 2 * 1024 * 1024 + 1)) }
    var error = CloudStreamAccumulator(provider: .chatCompletions)
    rejects { try error.consume(#"{"error":{"message":"secret"}}"#) }
    print("CloudStreamChecks: passed (split/interleaved tools, signatures, reasoning, termination, truncated/invalid/error/bounds rejection)")
  }

  static func rejects(_ action: () throws -> Void) {
    do { try action(); preconditionFailure("Unsafe partial stream accepted") } catch {}
  }
}
