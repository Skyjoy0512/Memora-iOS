import SwiftUI
import NaturalLanguage

/// Reveals text word by word, each word resolving through a small blur and
/// fade. Modelled on Transitions.dev's streaming text. Set `animates` to false
/// for text that is already settled, so scrolling back does not replay it.
struct StreamingText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var text: String
  var font: Font = .body
  var lineSpacing: CGFloat = 5
  var animates = true

  @State private var words: [String] = []
  @State private var revealed = 0

  private let gap = Duration.milliseconds(60)
  private let fade = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.35)

  var body: some View {
    FlowLayout(lineSpacing: lineSpacing) {
      ForEach(Array(words.enumerated()), id: \.offset) { index, word in
        Text(word)
          .font(font)
          .opacity(index < revealed ? 1 : 0)
          .blur(radius: index < revealed ? 0 : 1)
          .animation(fade, value: revealed)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
    .onAppear(perform: prepare)
    .onChange(of: text) { _, _ in prepare() }
  }

  private func prepare() {
    words = Self.tokenize(text)

    guard animates, !reduceMotion else {
      revealed = words.count
      return
    }

    revealed = 0
    Task {
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
