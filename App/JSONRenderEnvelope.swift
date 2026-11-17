import Foundation

/// Separates presentation protocols from prose without interpreting UI or tools.
struct JSONRenderEnvelope: Equatable {
  var markdown: String
  var segments: [Segment]
  var exceedsLimit: Bool

  struct Segment: Codable, Equatable {
    var format: String
    var text: String
    var complete: Bool
  }

  static let maximumBytes = 256 * 1_024
  static let fences: [String: String] = [
    "json-render": "json", "json-spec": "json", "spec": "patch",
    "yaml-spec": "yaml", "yaml-edit": "merge", "yaml-patch": "yamlPatch", "diff": "diff"
  ]

  static func parse(_ text: String, isStreaming: Bool = false) -> Self? {
    var prose: [String] = []
    var segments: [Segment] = []
    var activeFormat: String?
    var lines: [String] = []
    var ordinaryFence = false
    let source = text.components(separatedBy: "\n")
    for (index, line) in source.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if let format = activeFormat {
        if trimmed == "```" {
          segments.append(Segment(format: format, text: lines.joined(separator: "\n"), complete: true))
          activeFormat = nil
          lines = []
        } else { lines.append(line) }
        continue
      }
      if !ordinaryFence, trimmed.hasPrefix("```"), let format = fences[String(trimmed.dropFirst(3))] {
        activeFormat = format
        continue
      }
      if trimmed.hasPrefix("```") {
        if isStreaming, index == source.count - 1,
           fences.keys.contains(where: { ("```" + $0).hasPrefix(trimmed) }) {
          return Self(markdown: prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), segments: segments, exceedsLimit: false)
        }
        ordinaryFence.toggle()
        prose.append(line)
        continue
      }
      if !ordinaryFence, isPatchLine(trimmed) || (!ordinaryFence && isStreaming && index == source.count - 1 && trimmed.hasPrefix("{\"op\"")) {
        let complete = isPatchLine(trimmed) || !isStreaming || index < source.count - 1
        if segments.last?.format == "patch", segments.last?.complete == true {
          segments[segments.count - 1].text += "\n" + line
          segments[segments.count - 1].complete = complete
        } else { segments.append(Segment(format: "patch", text: line, complete: complete)) }
        continue
      }
      prose.append(line)
    }
    if let activeFormat {
      segments.append(Segment(format: activeFormat, text: lines.joined(separator: "\n"), complete: false))
    }
    guard !segments.isEmpty else { return nil }
    for index in segments.indices where segments[index].format == "json" {
      let value = segments[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
      if isPatchLine(value.components(separatedBy: "\n").first ?? "") { segments[index].format = "patch" }
    }
    return Self(markdown: prose.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
      segments: segments, exceedsLimit: segments.reduce(0) { $0 + $1.text.utf8.count } > maximumBytes)
  }

  private static func isPatchLine(_ text: String) -> Bool {
    guard text.hasPrefix("{"), let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    return (object["op"] is String && object["path"] is String) || object["__json_edit"] as? Bool == true
  }
}
