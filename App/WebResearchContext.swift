import Foundation

enum WebResearchContext {
  struct Value: Sendable { var text: String; var sent: [WebResearchSource] }
  static func build(_ sources: [WebResearchSource], budget: Int) -> Value {
    var text = "", sent: [WebResearchSource] = []
    for source in sources {
      let header = "【Web\(sent.count + 1)】\(source.title.prefix(100))（\(source.kind.label)）\n"
      let remaining = budget - text.count - header.count - 2
      guard remaining >= 50 else { break }
      var clipped = source
      clipped.text = String(source.text.prefix(min(2_000, remaining)))
      guard !clipped.text.isEmpty else { continue }
      text += header + clipped.text + "\n\n"
      sent.append(clipped)
    }
    return Value(text: text, sent: sent)
  }
  static func cited(_ answer: String, sent: [WebResearchSource]) -> [UUID] {
    guard let regex = try? NSRegularExpression(pattern: "【Web([0-9]+)】") else { return [] }
    var indices = Set<Int>()
    for match in regex.matches(in: answer, range: NSRange(answer.startIndex..., in: answer)) {
      if let range = Range(match.range(at: 1), in: answer), let value = Int(answer[range]), sent.indices.contains(value - 1) {
        indices.insert(value - 1)
      }
    }
    return indices.sorted().map { sent[$0].id }
  }

  static func linked(_ answer: String, sent: [WebResearchSource]) -> AttributedString {
    guard let regex = try? NSRegularExpression(pattern: "【Web([0-9]+)】") else { return AttributedString(answer) }
    var result = AttributedString()
    var cursor = answer.startIndex
    for match in regex.matches(in: answer, range: NSRange(answer.startIndex..., in: answer)) {
      guard let range = Range(match.range, in: answer), let numberRange = Range(match.range(at: 1), in: answer) else { continue }
      result.append(AttributedString(String(answer[cursor..<range.lowerBound])))
      if let number = Int(answer[numberRange]), sent.indices.contains(number - 1) {
        var marker = AttributedString(String(answer[range]))
        marker.link = sent[number - 1].url
        result.append(marker)
      }
      cursor = range.upperBound
    }
    result.append(AttributedString(String(answer[cursor...])))
    return result
  }
}
