import Foundation

@main
enum StreamingTextTailChecks {
  static func main() {
    var arriving = StreamingTextTail()
    for count in 0...4096 {
      let tail = StreamingTextTail().updating(to: count)
      precondition(tail.ranges.count <= 8)
      precondition(count - tail.start <= 64)
      precondition(tail.ranges.flatMap { Array($0) } == Array(tail.start..<count))
      let previousRanges = arriving.ranges
      arriving = arriving.updating(to: count)
      for range in previousRanges where range.lowerBound >= arriving.start {
        precondition(arriving.ranges.contains(range), "An appended token changed an earlier fade range")
      }
      precondition(arriving.ranges.count <= 8)
      precondition(count - arriving.start <= 64)
      for range in tail.ranges {
        precondition(StreamingTextTail.opacity(visibleCharacters: Double(range.lowerBound), range: range) == 0)
        precondition(StreamingTextTail.opacity(visibleCharacters: Double(range.upperBound), range: range) == 1)
        var previous = 0.0
        for step in 0...20 {
          let opacity = StreamingTextTail.opacity(visibleCharacters: Double(range.lowerBound) + Double(range.count * step) / 20, range: range)
          precondition(opacity >= previous && opacity >= 0 && opacity <= 1)
          previous = opacity
        }
      }
    }
    // Grapheme ranges must reconstruct Japanese, combining marks, emoji and
    // attributed links exactly; glyph counts and UTF-16 offsets cannot do this.
    var text = AttributedString(String(repeating: "本文👨‍👩‍👧‍👦e\u{301}العربية ", count: 20))
    text.link = URL(string: "memora://record/example")
    let tail = StreamingTextTail().updating(to: text.characters.count)
    let boundary = text.characters.index(text.characters.startIndex, offsetBy: tail.start)
    var rebuilt = AttributedString(text[..<boundary])
    var cursor = boundary
    for range in tail.ranges {
      let next = text.characters.index(cursor, offsetBy: range.count)
      rebuilt.append(AttributedString(text[cursor..<next]))
      cursor = next
    }
    precondition(rebuilt == text)
    let first = StreamingTextTail().updating(to: 3)
    precondition(first.updating(to: 6).ranges == [0..<3, 3..<6])
    precondition(first.updating(to: 2).ranges.isEmpty)
    precondition(first.updating(to: 3).ranges == first.ranges)
    precondition(first.updating(to: 10_000).ranges.count == 8)
    print("Streaming text tail passed: bounded ranges, stable boundaries, monotonic fades and Unicode/link preservation")
  }
}
