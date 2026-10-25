import Foundation

/// A partial tool call is data, never an executable call. Only a terminated,
/// validated provider turn is handed back to the existing agent runner.
struct CloudStreamAccumulator {
  static let maximumRetainedTextBytes = 2 * 1024 * 1024
  // SSE repeats a large JSON envelope for tiny deltas. DeepSeek's reasoning
  // can exhaust a 2MiB wire limit before the answer starts. Retained text and
  // individual events remain bounded separately from the total transfer.
  static let maximumSummaryWireBytes = 32 * 1024 * 1024
  enum Provider { case chatCompletions, anthropic }
  enum ResponseKind { case agentTurn, textCompletion }
  var provider: Provider
  var responseKind: ResponseKind = .agentTurn
  private(set) var text = ""
  private(set) var isFinished = false
  private(set) var outputEvents = 0
  private(set) var textEvents = 0
  private(set) var reasoningEvents = 0
  private var assistant: [String: Any] = ["role": "assistant"]
  private var hasChatText = false
  private var retainedTextBytes = 0
  private var blocks: [Int: [String: Any]] = [:]
  private var blockText: [Int: String] = [:]
  private var lastTextIndex = -1
  private var inputFragments: [Int: String] = [:]
  private var openBlocks: Set<Int> = []
  private(set) var finishReason: String?
  private var receivedBytes = 0
  private var usage: [String: Any]?

  mutating func consume(_ payload: String) throws {
    let limit = responseKind == .textCompletion ? Self.maximumSummaryWireBytes : Self.maximumRetainedTextBytes
    guard payload.utf8.count <= limit - receivedBytes, !isFinished else { throw AIAnswerFailure.executionLimit }
    receivedBytes += payload.utf8.count
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
      guard choices.count <= 1, choices.allSatisfy({ ($0["index"] as? Int ?? 0) == 0 }) else { throw AIAnswerFailure.server }
      for choice in choices where (choice["index"] as? Int ?? 0) == 0 {
        guard finishReason == nil else { throw AIAnswerFailure.server }
        if var delta = choice["delta"] as? [String: Any] {
          if !(delta["content"] as? String ?? "").isEmpty { textEvents += 1 }
          if ["reasoning_content", "reasoning"].contains(where: { !(delta[$0] as? String ?? "").isEmpty }) { reasoningEvents += 1 }
          if ["content", "reasoning_content", "reasoning"].contains(where: { !(delta[$0] as? String ?? "").isEmpty }) {
            outputEvents += 1
          }
          if responseKind == .textCompletion {
            if let calls = delta["tool_calls"], !(calls is NSNull) {
              guard let calls = calls as? [Any], calls.isEmpty else { throw AIAnswerFailure.server }
            }
            guard delta["function_call"] == nil || delta["function_call"] is NSNull else { throw AIAnswerFailure.server }
            delta = delta.filter { ["role", "content", "refusal"].contains($0.key) }
          }
          if let content = delta.removeValue(forKey: "content"), !(content is NSNull) {
            guard let piece = content as? String else { throw AIAnswerFailure.server }
            try retain(piece)
            hasChatText = true
            // Keep the growing buffer out of the Any dictionary. Aliasing it
            // there forces a full copy for every small token delta.
            text.append(piece)
          }
          assistant = try Self.merge(assistant, delta)
          guard (assistant["refusal"] as? String ?? "").utf8.count <= Self.maximumRetainedTextBytes else { throw AIAnswerFailure.executionLimit }
        }
        if let reason = choice["finish_reason"] as? String { finishReason = reason }
      }
      // A usage-only chunk may follow finish_reason; partial counters must not
      // refund the session's reserved output budget.
      if finishReason != nil, let finalUsage = object["usage"] as? [String: Any] { usage = finalUsage }
    case .anthropic:
      switch object["type"] as? String {
      case "ping": break
      case "message_start":
        usage = (object["message"] as? [String: Any])?["usage"] as? [String: Any]
        usage?.removeValue(forKey: "output_tokens")
      case "content_block_start":
        guard let index = object["index"] as? Int, (0..<64).contains(index), blocks[index] == nil,
              var block = object["content_block"] as? [String: Any] else { throw AIAnswerFailure.server }
        if !(block["text"] as? String ?? "").isEmpty || !(block["thinking"] as? String ?? "").isEmpty { outputEvents += 1 }
        if !(block["text"] as? String ?? "").isEmpty { textEvents += 1 }
        if !(block["thinking"] as? String ?? "").isEmpty { reasoningEvents += 1 }
        if responseKind == .textCompletion {
          guard ["text", "thinking", "redacted_thinking"].contains(block["type"] as? String ?? "") else { throw AIAnswerFailure.server }
          block = block.filter { ["type", "text"].contains($0.key) }
        }
        if block["type"] as? String == "text" {
          guard let piece = block.removeValue(forKey: "text") as? String else { throw AIAnswerFailure.server }
          try appendBlockText(piece, index: index)
        }
        blocks[index] = block
        openBlocks.insert(index)
      case "content_block_delta":
        guard let index = object["index"] as? Int, openBlocks.contains(index),
              var block = blocks[index], let delta = object["delta"] as? [String: Any] else { throw AIAnswerFailure.server }
        switch delta["type"] as? String {
        case "text_delta":
          guard block["type"] as? String == "text", let piece = delta["text"] as? String else { throw AIAnswerFailure.server }
          if !(delta["text"] as? String ?? "").isEmpty { outputEvents += 1 }
          if !(delta["text"] as? String ?? "").isEmpty { textEvents += 1 }
          try appendBlockText(piece, index: index)
        case "thinking_delta":
          if !(delta["thinking"] as? String ?? "").isEmpty { outputEvents += 1 }
          if !(delta["thinking"] as? String ?? "").isEmpty { reasoningEvents += 1 }
          if responseKind == .agentTurn { block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "") }
        case "signature_delta":
          if responseKind == .agentTurn { block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "") }
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
      case "message_delta":
        if let reason = (object["delta"] as? [String: Any])?["stop_reason"] as? String {
          finishReason = reason
          // message_delta counts are cumulative, never increments.
          if let finalUsage = object["usage"] as? [String: Any] {
            usage = (usage ?? [:]).merging(finalUsage) { _, latest in latest }
          }
        }
      case "message_stop":
        guard openBlocks.isEmpty, finishReason != nil else { throw AIAnswerFailure.connectionLost }
        isFinished = true
      default: throw AIAnswerFailure.server
      }
    }
  }

  func response() throws -> [String: Any] {
    guard isFinished else { throw AIAnswerFailure.connectionLost }
    if provider == .anthropic {
      let content = blocks.keys.sorted().compactMap { index -> [String: Any]? in
        guard var block = blocks[index] else { return nil }
        if let text = blockText[index] { block["text"] = text }
        return block
      }
      var response: [String: Any] = ["content": content, "stop_reason": finishReason ?? ""]
      if let usage { response["usage"] = usage }
      if responseKind == .textCompletion { _ = try CloudSummaryResponse(response, provider: provider) }
      else { _ = try CloudAgentTurnDecoder.anthropic(response) }
      return response
    }
    var message = assistant
    if hasChatText { message["content"] = text }
    if let calls = message["tool_calls"] as? [[String: Any]] {
      message["tool_calls"] = calls.map { call in var call = call; call.removeValue(forKey: "index"); return call }
    }
    var response: [String: Any] = ["choices": [["message": message, "finish_reason": finishReason ?? ""]]]
    if let usage { response["usage"] = usage }
    if responseKind == .textCompletion { _ = try CloudSummaryResponse(response, provider: provider) }
    else { _ = try CloudAgentTurnDecoder.chatCompletions(response) }
    return response
  }

  private mutating func retain(_ piece: String) throws {
    let bytes = piece.utf8.count
    guard bytes <= Self.maximumRetainedTextBytes - retainedTextBytes else { throw AIAnswerFailure.executionLimit }
    retainedTextBytes += bytes
  }

  private mutating func appendBlockText(_ piece: String, index: Int) throws {
    try retain(piece)
    blockText[index, default: ""].append(piece)
    if index >= lastTextIndex {
      text.append(piece)
      lastTextIndex = index
    } else {
      // Interleaved blocks must still render in provider index order.
      text = blockText.keys.sorted().compactMap { blockText[$0] }.joined()
    }
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
