import SwiftUI

/// Keeps Markdown links and selection native while only the arriving tail fades in.
struct MarkdownInlineText: View {
  @Environment(\.streamsMarkdownText) private var isStreaming
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var markdown: String
  @State private var revealedCharacters: Double = 0
  @State private var hasStreamed = false
  @State private var tail = StreamingTextTail()

  var body: some View {
    let attributed = InlineMarkdownEditor.attributed(markdown)
    let count = attributed.characters.count
    let animatesTail = !reduceMotion && (isStreaming || hasStreamed)
    let currentTail = tail.updating(to: count)
    Group {
      if animatesTail {
        rendered(attributed, tail: currentTail)
          .textRenderer(StreamingTailRenderer(visibleCharacters: revealedCharacters))
      } else {
        Text(attributed)
      }
    }
    .onAppear {
      hasStreamed = isStreaming
      tail = currentTail
      reveal(count, animated: isStreaming)
    }
    .onChange(of: markdown) { _, _ in
      hasStreamed = hasStreamed || isStreaming
      tail = currentTail
      reveal(count, animated: isStreaming || hasStreamed)
    }
    .onChange(of: reduceMotion) { _, reduced in
      if reduced { revealedCharacters = Double(count) }
    }
  }

  private func rendered(_ attributed: AttributedString, tail: StreamingTextTail) -> Text {
    let characters = attributed.characters
    // A bounded tail keeps a large network burst readable immediately and
    // avoids per-glyph work across an ever-growing answer on every frame.
    var cursor = characters.index(characters.startIndex, offsetBy: tail.start)
    var result = Text(AttributedString(attributed[..<cursor]))
    for range in tail.ranges {
      let next = characters.index(cursor, offsetBy: range.count)
      let fragment = Text(AttributedString(attributed[cursor..<next]))
        .customAttribute(StreamingTailRange(range: range))
      result = Text("\(result)\(fragment)")
      cursor = next
    }
    return result
  }

  private func reveal(_ count: Int, animated: Bool) {
    guard !reduceMotion, animated, Double(count) >= revealedCharacters else {
      revealedCharacters = Double(count)
      return
    }
    withAnimation(.smooth(duration: 0.2)) { revealedCharacters = Double(count) }
  }
}

extension EnvironmentValues {
  @Entry var streamsMarkdownText = false
}
