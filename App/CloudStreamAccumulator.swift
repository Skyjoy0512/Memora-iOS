import Foundation

/// A partial tool call is data, never an executable call. Only a terminated,
/// validated provider turn is handed back to the existing agent runner.
struct CloudStreamAccumulator {
  enum Provider { case chatCompletions, anthropic }
  var provider: Provider
  private(set) var text = ""
  private(set) var isFinished = false
  private var assistant: [String: Any] = ["role": "assistant"]
  private var blocks: [Int: [String: Any]] = [:]
  private var inputFragments: [Int: String] = [:]
  private var openBlocks: Set<Int> = []
  private var finishReason: String?
  private var receivedBytes = 0

  mutating func consume(_ payload: String) throws {
    receivedBytes += payload.utf8.count
    guard receivedBytes <= 2 * 1024 * 1024, !isFinished else { throw AIAnswerFailure.server }
    if payload == "[DONE]" {
      guard provider == .chatCompletions, finishReason != nil else { throw AIAnswerFailure.connectionLost }
      isFinished = true
      return
    }
    guard let data = payload.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["error"] == nil else { throw AIAnswerFailure.server }
    switch provider {
    case .chatCompletions:
      guard let choices = object["choices"] as? [[String: Any]] else { throw AIAnswerFailure.server }
      for choice in choices where (choice["index"] as? Int ?? 0) == 0 {
        if let delta = choice["delta"] as? [String: Any] {
          assistant = try Self.merge(assistant, delta)
          text = assistant["content"] as? String ?? ""
        }
        if let reason = choice["finish_reason"] as? String { finishReason = reason }
      }
    case .anthropic:
      switch object["type"] as? String {
      case "message_start", "ping": break
      case "content_block_start":
        guard let index = object["index"] as? Int, (0..<64).contains(index), blocks[index] == nil,
              let block = object["content_block"] as? [String: Any] else { throw AIAnswerFailure.server }
        blocks[index] = block
        openBlocks.insert(index)
      case "content_block_delta":
        guard let index = object["index"] as? Int, openBlocks.contains(index),
              var block = blocks[index], let delta = object["delta"] as? [String: Any] else { throw AIAnswerFailure.server }
        switch delta["type"] as? String {
        case "text_delta": block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
        case "thinking_delta": block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
        case "signature_delta": block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
        case "input_json_delta": inputFragments[index, default: ""] += delta["partial_json"] as? String ?? ""
        default: throw AIAnswerFailure.server
        }
        blocks[index] = block
      case "content_block_stop":
        guard let index = object["index"] as? Int, openBlocks.remove(index) != nil else { throw AIAnswerFailure.server }
        if let fragment = inputFragments[index] {
          guard let data = fragment.data(using: .utf8),
                let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIAnswerFailure.server }
          blocks[index]?["input"] = input
        }
      case "message_delta": finishReason = (object["delta"] as? [String: Any])?["stop_reason"] as? String
      case "message_stop":
        guard openBlocks.isEmpty, finishReason != nil else { throw AIAnswerFailure.connectionLost }
        isFinished = true
      default: throw AIAnswerFailure.server
      }
      text = blocks.keys.sorted().compactMap { blocks[$0]?["text"] as? String }.joined()
    }
  }

  func response() throws -> [String: Any] {
    guard isFinished else { throw AIAnswerFailure.connectionLost }
    guard finishReason != "length", finishReason != "max_tokens" else { throw AIAnswerFailure.connectionLost }
    guard finishReason != "refusal", finishReason != "content_filter" else { throw AIAnswerFailure.refused }
    if provider == .anthropic {
      return ["content": blocks.keys.sorted().compactMap { blocks[$0] }, "stop_reason": finishReason ?? ""]
    }
    var message = assistant
    if let calls = message["tool_calls"] as? [[String: Any]] {
      guard calls.count <= 24 else { throw AIAnswerFailure.server }
      var identifiers: Set<String> = []
      for call in calls {
        guard let id = call["id"] as? String, !id.isEmpty, identifiers.insert(id).inserted,
              let function = call["function"] as? [String: Any], let name = function["name"] as? String, !name.isEmpty,
              let arguments = function["arguments"] as? String, let data = arguments.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { throw AIAnswerFailure.server }
      }
      message["tool_calls"] = calls.map { call in var call = call; call.removeValue(forKey: "index"); return call }
    }
    return ["choices": [["message": message]]]
  }

  /// Preserve provider-specific reasoning/signatures alongside indexed tool
  /// deltas; rebuilding only the standard fields loses provider context.
  private static func merge(_ old: [String: Any], _ delta: [String: Any]) throws -> [String: Any] {
    var result = old
    for (key, value) in delta where !(value is NSNull) {
      if let items = value as? [[String: Any]] {
        var accumulated = result[key] as? [[String: Any]] ?? []
        for item in items {
          if let index = item["index"] as? Int {
            guard (0..<64).contains(index) else { throw AIAnswerFailure.server }
            if let position = accumulated.firstIndex(where: { $0["index"] as? Int == index }) {
              accumulated[position] = try merge(accumulated[position], item)
            } else { accumulated.append(item) }
          } else { accumulated.append(item) }
        }
        result[key] = accumulated.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
      } else if let object = value as? [String: Any] {
        result[key] = try merge(result[key] as? [String: Any] ?? [:], object)
      } else if let piece = value as? String, key != "role", key != "type" {
        result[key] = (result[key] as? String ?? "") + piece
      } else { result[key] = value }
    }
    return result
  }
}
