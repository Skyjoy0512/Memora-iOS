import SwiftUI
import NaturalLanguage

/// Reveals an answer word by word: each new word fades in and rises a hair.
/// Modelled on Transitions.dev's streaming text. The words carry their inline
/// markdown (bold, italics, code), so a formatted answer reads the same while
/// it arrives as it does once settled. Set `animates` to false for text that is
/// already settled, so scrolling back does not replay it.
///
/// Long answers and finished reveals fall back to one ordinary, selectable
/// `Text`, so a long reply can still be copied, read aloud, and line-broken
/// normally.
struct StreamingText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var text: String
  var font: Font = .body
  var lineSpacing: CGFloat = 5
  var animates = true
  /// What the word-by-word reveal shows, when it differs from the settled
  /// text (citations are links only once settled).
  var revealText: String?

  @State private var words: [String] = []
  @State private var births: [Double] = []
  @State private var revealed = 0
  @State private var start = Date()
  @State private var revealTask: Task<Void, Never>?

  /// Above this, the word-by-word reveal is skipped entirely.
  private let plainTextThreshold = 240
  private let gap = Duration.milliseconds(60)
  private let fade = 0.35

  var body: some View {
    Group {
      if usesPlainText {
        // Answers often come back as markdown lists, headings or bold; once
        // settled they are drawn as a document instead of showing the markers.
        if MarkdownBlockParser.hasInlineOrBlockMarkdown(text) || text.contains("](") {
          MarkdownDocumentView(markdown: text)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
        } else {
          Text(text)
            .font(font)
            .lineSpacing(lineSpacing)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        streamingReveal
      }
    }
    .onAppear(perform: prepare)
    .onChange(of: text) { _, _ in prepare() }
    .onDisappear { revealTask?.cancel() }
  }

  /// Long text, settled text, and text with motion turned off are drawn as one
  /// plain `Text`.
  private var usesPlainText: Bool {
    !animates || reduceMotion || text.count > plainTextThreshold || revealed >= words.count
  }

  /// Words light up as they arrive. `TimelineView` drives the fade each frame
  /// while there is still a word to show.
  private var streamingReveal: some View {
    TimelineView(.animation(paused: reduceMotion)) { context in
      let now = context.date.timeIntervalSince(start)
      rendererText()
        .textRenderer(TokenFade(now: now, births: births, fade: fade))
    }
    .font(font)
    .lineSpacing(lineSpacing)
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
  }

  /// Each word carries its own index, so the renderer can fade it in when its
  /// turn comes; the whitespace after a word rides with it, so runs stay
  /// contiguous. Inline markdown is parsed first, so a bold word arrives bold
  /// instead of showing its `**`.
  private func rendererText() -> Text {
    let source = Self.inline(revealText ?? text)
    var result = Text(verbatim: "")
    for (index, range) in Self.tokenRanges(in: source).enumerated() {
      result = result + Text(AttributedString(source[range])).customAttribute(TokenIndex(index: index))
    }
    return result
  }

  /// The reveal text with its inline markdown applied. Whitespace, including
  /// line breaks, is kept so the layout matches the settled document.
  private static func inline(_ text: String) -> AttributedString {
    var result = (try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
    for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
      result[run.range].backgroundColor = Color.primary.opacity(0.08)
    }
    return result
  }

  private func prepare() {
    revealTask?.cancel()

    guard animates, !reduceMotion, text.count <= plainTextThreshold else {
      words = []
      births = []
      revealed = 0
      return
    }

    words = Self.tokenize(revealText ?? text)
    births = Array(repeating: .greatestFiniteMagnitude, count: words.count)
    revealed = 0
    start = Date()
    revealTask = Task { @MainActor in
      var count = 0
      for _ in words {
        try? await Task.sleep(for: gap)
        guard !Task.isCancelled else { return }
        if births.indices.contains(count) {
          births[count] = Date().timeIntervalSince(start)
        }
        count += 1
        revealed = count
      }
    }
  }

  /// Splits into words, keeping each word's leading space so spacing survives.
  /// `NLTokenizer` handles languages without spaces, like Japanese.
  private static func tokenize(_ text: String) -> [String] {
    guard !text.isEmpty else { return [] }

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text

    var tokens: [String] = []
    var cursor = text.startIndex
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      tokens.append(String(text[cursor..<range.upperBound]))
      cursor = range.upperBound
      return true
    }
    if cursor < text.endIndex {
      tokens.append(String(text[cursor...]))
    }
    return tokens.isEmpty ? [text] : tokens
  }

  /// The word ranges on the attributed string, each carrying the whitespace
  /// that follows it, so the renderer can fade one word at a time.
  private static func tokenRanges(in source: AttributedString) -> [Range<AttributedString.Index>] {
    let characters = source.characters
    var ranges: [Range<AttributedString.Index>] = []
    var start = characters.startIndex
    var previousWasSpace = false
    var index = characters.startIndex
    while index < characters.endIndex {
      let isSpace = characters[index].isWhitespace
      if !isSpace, previousWasSpace, index > start {
        ranges.append(start..<index)
        start = index
      }
      previousWasSpace = isSpace
      index = characters.index(after: index)
    }
    if start < characters.endIndex {
      ranges.append(start..<characters.endIndex)
    }
    return ranges
  }
}

/// A word's place in the reveal, read back by the renderer.
private struct TokenIndex: TextAttribute {
  let index: Int
}

/// Draws each word at its fade-in opacity with a 2pt rise.
private struct TokenFade: TextRenderer {
  var now: Double
  var births: [Double]
  var fade: Double

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      for run in line {
        var opacity = 1.0
        if let token = run[TokenIndex.self], births.indices.contains(token.index) {
          opacity = min(max((now - births[token.index]) / fade, 0), 1)
        }
        var local = context
        local.opacity = opacity
        local.translateBy(x: 0, y: (1 - opacity) * 2)
        local.draw(run)
      }
    }
  }
}
