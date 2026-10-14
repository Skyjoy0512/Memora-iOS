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
      if isStreaming {
        Text(response.markdown).font(.body).lineSpacing(5).textSelection(.enabled)
      } else {
        StreamingText(text: response.markdown, lineSpacing: 5, animates: false)
        if let interface = response.interface { NativeAIInterfaceView(interface: interface, messageID: messageID) }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
