import Foundation

/// Only the unfinished paragraph is parsed again. Complete blocks retain their positions.
struct IncrementalMarkdown {
  private(set) var settled: [MarkdownBlock] = []
  private(set) var tail: [MarkdownBlock] = []
  private(set) var parsedBytes = 0
  private var previous = ""
  private var pending = ""
  private var scannedBytes = 0
  private var lineStart = 0
  private var fence: MarkdownFence?
  private var finished = false

  var blocks: [MarkdownBlock] { settled + tail }

  mutating func update(_ text: String, isStreaming: Bool) {
    if text == previous && (isStreaming || finished) { return }
    if finished || !text.utf8.starts(with: previous.utf8) { self = Self() }
    pending += String(decoding: text.utf8.dropFirst(previous.utf8.count), as: UTF8.self)
    previous = text
    let bytes = pending.utf8
    var committed = 0
    for offset in scannedBytes..<bytes.count {
      let index = bytes.index(bytes.startIndex, offsetBy: offset)
      guard bytes[index] == 10 else { continue }
      let start = bytes.index(bytes.startIndex, offsetBy: lineStart)
      let line = String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: .newlines)
      if let open = fence {
        if open.closes(line) { fence = nil }
      } else if let open = MarkdownFence(line) {
        fence = open
      } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
        committed = offset + 1
      }
      lineStart = offset + 1
    }
    scannedBytes = bytes.count
    if !isStreaming { committed = bytes.count; finished = true }
    if committed > 0 {
      let end = bytes.index(bytes.startIndex, offsetBy: committed)
      let complete = String(decoding: bytes[..<end], as: UTF8.self)
      settled += parse(complete)
      pending = String(decoding: bytes[end...], as: UTF8.self)
      scannedBytes -= committed
      lineStart = max(0, lineStart - committed)
    }
    tail = pending.isEmpty ? [] : parse(pending)
  }

  private mutating func parse(_ text: String) -> [MarkdownBlock] {
    parsedBytes += text.utf8.count
    // Streaming snapshots must not fill the settled-document cache.
    return MarkdownBlockParser.sourcedBlocks(for: text).map(\.block)
  }
}
