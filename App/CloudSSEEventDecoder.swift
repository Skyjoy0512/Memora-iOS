import Foundation

/// Foundation's AsyncLineSequence omits empty lines, which carry SSE boundaries.
/// Count wire bytes before buffering, including peers that never send a newline.
struct CloudSSEEventDecoder {
  var maximumBytes = AgentSessionBudget.maximumResponseBytes
  private(set) var receivedBytes = 0
  private var line: [UInt8] = []
  private var dataLines: [String] = []
  private var followsCR = false
  private var firstLine = true

  mutating func consume(_ byte: UInt8) throws -> String? {
    guard receivedBytes < maximumBytes else { throw AIAnswerFailure.executionLimit }
    receivedBytes += 1
    if followsCR {
      followsCR = false
      if byte == 10 { return nil }
    }
    if byte == 10 || byte == 13 {
      followsCR = byte == 13
      return try finishLine()
    }
    line.append(byte)
    return nil
  }

  /// Compatible endpoints sometimes omit the last event's empty line. The
  /// accumulator still requires an explicit, validated provider terminator.
  mutating func finish() throws -> String? {
    if let payload = try finishLine() { return payload }
    return dispatch()
  }

  private mutating func finishLine() throws -> String? {
    guard var text = String(bytes: line, encoding: .utf8) else { throw AIAnswerFailure.server }
    line.removeAll(keepingCapacity: true)
    if firstLine {
      firstLine = false
      if text.first == "\u{FEFF}" { text.removeFirst() }
    }
    if text.isEmpty { return dispatch() }
    if text == "data" { dataLines.append("") }
    else if text.hasPrefix("data:") {
      let value = text.dropFirst(5)
      dataLines.append(String(value.first == " " ? value.dropFirst() : value))
    }
    return nil
  }

  private mutating func dispatch() -> String? {
    guard !dataLines.isEmpty else { return nil }
    let payload = dataLines.joined(separator: "\n")
    dataLines.removeAll(keepingCapacity: true)
    return payload
  }
}
