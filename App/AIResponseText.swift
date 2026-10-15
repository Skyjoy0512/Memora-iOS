import SwiftUI

/// Network arrival drives live text. Settled answers share the same selectable
/// Markdown renderer without restarting a second word-by-word animation.
struct AIResponseText: View {
  var text: String
  var isStreaming = false
  var messageID: UUID?

  var body: some View {
    let response = NativeAIInterface.response(text, isStreaming: isStreaming)
    VStack(alignment: .leading, spacing: 18) {
      StreamingMarkdownView(text: response.markdown, isStreaming: isStreaming)
      if !isStreaming {
        if let interface = response.interface { NativeAIInterfaceView(interface: interface, messageID: messageID) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
