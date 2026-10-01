import SwiftUI
import NaturalLanguage

/// Reveals text word by word, each word resolving through a small blur and
/// fade. Modelled on Transitions.dev's streaming text. Set `animates` to false
/// for text that is already settled, so scrolling back does not replay it.
///
/// Long answers and finished reveals fall back to one ordinary, selectable
/// `Text`, so a long reply is not split into a view per word and can still be
/// copied, read aloud, and line-broken normally.
struct StreamingText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var text: String
  var font: Font = .body
  var lineSpacing: CGFloat = 5
  var animates = true

  @State private var words: [String] = []
  @State private var revealed = 0
  @State private var revealTask: Task<Void, Never>?

  /// Above this, the word-by-word reveal is skipped entirely.
  private let plainTextThreshold = 240
  private let gap = Duration.milliseconds(60)
  private let fade = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)

  var body: some View {
    Group {
      if usesPlainText {
        // Answers often come back as markdown lists, headings or bold; once
        // settled they are drawn as a document instead of showing the markers.
        if MarkdownBlockParser.hasInlineOrBlockMarkdown(text) {
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
        FlowLayout(lineSpacing: lineSpacing) {
          ForEach(Array(words.enumerated()), id: \.offset) { index, word in
            Text(word)
              .font(font)
              .opacity(index < revealed ? 1 : 0)
              .blur(radius: index < revealed ? 0 : 1)
              .animation(fade, value: revealed)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
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

  private func prepare() {
    revealTask?.cancel()

    guard animates, !reduceMotion, text.count <= plainTextThreshold else {
      words = []
      revealed = 0
      return
    }

    words = Self.tokenize(text)
    revealed = 0
    revealTask = Task { @MainActor in
      var count = 0
      for _ in words {
        try? await Task.sleep(for: gap)
        guard !Task.isCancelled else { return }
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
}
