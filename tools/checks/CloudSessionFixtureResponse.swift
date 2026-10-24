import Foundation

enum CloudSessionFixtureResponse {
  static func json(provider: LLMProvider, calls: [AgentToolCall] = [], text: String = "完了", finish: String? = nil) throws -> CloudSessionFixtureProtocol.Reply {
    let object: [String: Any]
    if provider.usesAnthropicAPI {
      object = ["content": [["type": "thinking", "thinking": "架空の検討", "signature": "fixture-signature"]] +
        [["type": "text", "text": text]] + calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.arguments] },
        "stop_reason": finish ?? (calls.isEmpty ? "end_turn" : "tool_use"), "usage": ["output_tokens": 12]]
    } else {
      object = ["choices": [["message": ["role": "assistant", "content": text, "reasoning_content": "架空の検討",
        "tool_calls": try calls.map { call in ["id": call.id, "type": "function", "function": ["name": call.name,
          "arguments": String(decoding: try JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys]), as: UTF8.self)]] }],
        "finish_reason": finish ?? (calls.isEmpty ? "stop" : "tool_calls")]], "usage": ["completion_tokens": 12]]
    }
    return .init(data: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
  }

  static func sse(provider: LLMProvider, calls: [AgentToolCall] = [], text: String = "", terminated: Bool = true, finish: String? = nil) throws -> CloudSessionFixtureProtocol.Reply {
    var events: [[String: Any]] = []
    if provider.usesAnthropicAPI {
      events.append(["type": "message_start", "message": ["usage": ["input_tokens": 10, "output_tokens": 0]]])
      events += [
        ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
        ["type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": "架空の検討"]],
        ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "fixture-signature"]],
        ["type": "content_block_stop", "index": 0],
        ["type": "content_block_start", "index": 1, "content_block": ["type": "text", "text": ""]]
      ]
      for piece in [String(text.prefix(text.count / 2)), String(text.dropFirst(text.count / 2))] {
        events.append(["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": piece]])
      }
      events.append(["type": "content_block_stop", "index": 1])
    } else {
      events.append(["choices": [["index": 0, "delta": ["role": "assistant", "reasoning_content": "架空の検討", "content": text]]]])
    }
    for (index, call) in calls.enumerated() {
      let arguments = String(decoding: try JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys]), as: UTF8.self)
      let pieces = [String(arguments.prefix(arguments.count / 2)), String(arguments.dropFirst(arguments.count / 2))]
      if provider.usesAnthropicAPI {
        let block = index + 2
        events.append(["type": "content_block_start", "index": block,
          "content_block": ["type": "tool_use", "id": call.id, "name": call.name, "input": [:]]])
        for piece in pieces { events.append(["type": "content_block_delta", "index": block, "delta": ["type": "input_json_delta", "partial_json": piece]]) }
        events.append(["type": "content_block_stop", "index": block])
      } else {
        events.append(["choices": [["index": 0, "delta": ["tool_calls": [["index": index, "id": call.id, "type": "function", "function": ["name": call.name, "arguments": pieces[0]]]]]]]])
        events.append(["choices": [["index": 0, "delta": ["tool_calls": [["index": index, "function": ["arguments": pieces[1]]]]]]]])
      }
    }
    if provider.usesAnthropicAPI {
      events.append(["type": "message_delta", "delta": ["stop_reason": finish ?? (calls.isEmpty ? "end_turn" : "tool_use")], "usage": ["output_tokens": 12]])
      if terminated { events.append(["type": "message_stop"]) }
    } else {
      events.append(["choices": [["index": 0, "delta": [:], "finish_reason": finish ?? (calls.isEmpty ? "stop" : "tool_calls")]]])
      events.append(["choices": [], "usage": ["completion_tokens": 12]])
    }
    let lines = try events.map { "data: " + String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self) }
    let wire = ": fixture only\r\n\r\n" + lines.joined(separator: "\r\n\r\n") + "\r\n\r\n" +
      (!provider.usesAnthropicAPI && terminated ? "data: [DONE]\r\n\r\n" : "")
    return .init(data: Data(wire.utf8), contentType: "text/event-stream", chunkSize: 7)
  }
}
