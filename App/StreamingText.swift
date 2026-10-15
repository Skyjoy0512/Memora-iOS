import SwiftUI

/// Compatibility surface for settled answers and their citation links.
/// Arrival drives live text; no timer or language-dependent word splitting.
struct StreamingText: View {
  var text: String
  var font: Font = .body
  var lineSpacing: CGFloat = 5
  var animates = true
  var revealText: String?

  var body: some View {
    StreamingMarkdownView(text: text, isStreaming: false)
      .font(font)
      .lineSpacing(lineSpacing)
  }
}
