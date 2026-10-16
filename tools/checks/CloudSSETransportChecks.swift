import Foundation

@main
struct CloudSSETransportChecks {
  @MainActor
  static func main() async throws {
    let first = #"{"choices":[{"index":0,"delta":{"content":"こんにちは👨‍👩‍👧‍👦"}}]}"#
    let last = #"{"index":0,"delta":{"content":"。"},"finish_reason":"stop"}]}"#
    for newline in ["\n", "\r\n", "\r"] {
      let frames = [
        "\u{FEFF}: connection comment",
        "event: message\(newline)data: \(first)",
        ": keepalive",
        "data: {\"choices\": [\(newline)data: \(last)",
        "data: [DONE]"
      ]
      let wire = (frames.joined(separator: newline + newline) + newline + newline)
      let result = try await receive(wire, provider: .chatCompletions)
      precondition(result.text == "こんにちは👨‍👩‍👧‍👦。" && result.publications == 2)
      precondition(result.beforeTerminator, "No text delivered until completion")
    }

    let claude = [
      #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
      #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"日本語の回答"}}"#,
      #"{"type":"content_block_stop","index":0}"#,
      #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
      #"{"type":"message_stop"}"#
    ].map { "data: \($0)\n\n" }.joined()
    let anthropic = try await receive(claude, provider: .anthropic)
    precondition(anthropic.text == "日本語の回答" && anthropic.beforeTerminator)

    // Preserve the existing EOF compatibility, but never invent a terminator.
    let withoutFinalNewline = "data: \(first)\n\ndata: {\"choices\":[\(last)\n\ndata: [DONE]"
    let eof = try await receive(withoutFinalNewline, provider: .chatCompletions)
    precondition(eof.text == "こんにちは👨‍👩‍👧‍👦。")
    do {
      _ = try await receive("data: \(first)\n\n", provider: .chatCompletions)
      preconditionFailure("Truncated SSE accepted")
    } catch AIAnswerFailure.connectionLost {}

    var events = CloudSSEEventDecoder()
    var payloads: [String] = []
    for byte in Data("data:\ndata:  spaced \n\nignored: value\n\n".utf8) {
      if let value = try events.consume(byte) { payloads.append(value) }
    }
    precondition(payloads == ["\n spaced "])
    let afterFinish = try events.finish()
    precondition(afterFinish == nil)
    var invalid = CloudSSEEventDecoder()
    _ = try invalid.consume(0xff)
    do { _ = try invalid.consume(10); preconditionFailure("Invalid UTF-8 accepted") }
    catch AIAnswerFailure.server {}
    var bounded = CloudSSEEventDecoder(maximumBytes: 16_384)
    for _ in 0..<16_384 { _ = try bounded.consume(120) }
    do { _ = try bounded.consume(120); preconditionFailure("Oversized unterminated line accepted") }
    catch AIAnswerFailure.executionLimit {}
    precondition(bounded.receivedBytes == 16_384)
    var exact = CloudSSEEventDecoder(maximumBytes: 0)
    let empty = try exact.finish()
    precondition(empty == nil)
    do { _ = try exact.consume(120); preconditionFailure("Zero-byte bound accepted input") }
    catch AIAnswerFailure.executionLimit {}

    let rapid = ["A", "B", "C"].map { value in
      "data: {\"choices\":[{\"delta\":{\"content\":\"\(value)\"}}]}\n\n"
    }.joined() + "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    let start = ContinuousClock.now
    var tick: Int64 = 0
    var updates: [String] = []
    _ = try await CloudTurnStreamReader.response(from: Bytes(data: Data(rapid.utf8), probe: Probe()), provider: .chatCompletions, now: {
      defer { tick += 1 }
      return start.advanced(by: .milliseconds(tick))
    }, onText: { updates.append($0) })
    precondition(updates == ["A", "ABC"], "First delta or final flush lost; rapid updates not coalesced")
    tick = 0
    updates = []
    _ = try await CloudTurnStreamReader.response(from: Bytes(data: Data(rapid.utf8), probe: Probe()), provider: .chatCompletions, now: {
      defer { tick += 1 }
      return start.advanced(by: .milliseconds(tick * 100))
    }, onText: { updates.append($0) })
    precondition(updates == ["A", "AB", "ABC"], "100ms publication cadence changed or finish replayed")

    for cancelAt in [0, 10] {
      let stopped = Task { @MainActor in
        var emitted = false
        do {
          _ = try await CloudTurnStreamReader.response(from: Bytes(data: Data(rapid.utf8), probe: Probe(), cancelAt: cancelAt), provider: .chatCompletions, onText: { _ in emitted = true })
          return false
        } catch is CancellationError { return !emitted }
        catch { return false }
      }
      let rejected = await stopped.value
      precondition(rejected)
    }
    do {
      _ = try await CloudTurnStreamReader.response(from: Bytes(data: Data(rapid.utf8), probe: Probe(), failAt: 10), provider: .chatCompletions, onText: { _ in preconditionFailure("Published before first complete event") })
      preconditionFailure("Network failure swallowed")
    } catch ProbeFailure.disconnected {}
    #if DEBUG
    let fixture = "# 見出し\n\n日本語👨‍👩‍👧‍👦e\u{301}\n\n```swift\nlet x = 1\n```\n"
    let fixtureResponse = try await CloudTurnStreamReader.response(from: SyntheticAIEventStream(text: fixture, interval: .zero), provider: .chatCompletions, onText: { _ in })
    let fixtureTurn = try CloudAgentTurnDecoder.chatCompletions(fixtureResponse)
    precondition(fixtureTurn.text == fixture.trimmingCharacters(in: .whitespacesAndNewlines))
    #endif
    print("CloudSSETransportChecks: passed (actual bounded wire → event decoder → accumulator → turn decoder; incremental publication, LF/CRLF/CR, BOM/comments/multiline, EOF, truncated/invalid rejection; no network)")
  }

  @MainActor
  static func receive(_ wire: String, provider: CloudStreamAccumulator.Provider) async throws -> (text: String, publications: Int, beforeTerminator: Bool) {
    let probe = Probe()
    let bytes = Bytes(data: Data(wire.utf8), probe: probe)
    var publications = 0
    var beforeTerminator = false
    let response = try await CloudTurnStreamReader.response(from: bytes, provider: provider, onText: { _ in
      publications += 1
      if probe.pulls < wire.utf8.count { beforeTerminator = true }
    })
    let turn = try provider == .anthropic ? CloudAgentTurnDecoder.anthropic(response) : CloudAgentTurnDecoder.chatCompletions(response)
    return (turn.text, publications, beforeTerminator)
  }

  final class Probe { var pulls = 0 }
  enum ProbeFailure: Error { case disconnected }

  struct Bytes: AsyncSequence {
    var data: Data
    var probe: Probe
    var cancelAt: Int? = nil
    var failAt: Int? = nil
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(input: self) }
    struct AsyncIterator: AsyncIteratorProtocol {
      var input: Bytes
      var offset = 0
      mutating func next() async throws -> UInt8? {
        input.probe.pulls += 1
        if offset == input.cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
        if offset == input.failAt { throw ProbeFailure.disconnected }
        guard offset < input.data.count else { return nil }
        defer { offset += 1 }
        return input.data[offset]
      }
    }
  }
}
