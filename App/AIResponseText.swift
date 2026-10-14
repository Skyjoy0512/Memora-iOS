import SwiftUI

/// Network arrival drives live text. Settled answers share the same selectable
/// Markdown renderer without restarting a second word-by-word animation.
struct AIResponseText: View {
  var text: String
  var isStreaming = false

  var body: some View {
    Group {
      if isStreaming {
        Text(text).font(.body).lineSpacing(5).textSelection(.enabled)
      } else {
        StreamingText(text: text, lineSpacing: 5, animates: false)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
