import SwiftUI

/// Network arrival drives live text. Settled answers share the same selectable
/// Markdown renderer without restarting a second word-by-word animation.
struct AIResponseText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var text: String
  var isStreaming = false
  var messageID: UUID?
  @State private var cache = NativeAIResponseCache()
  @State private var introductionProgress: Double
  @State private var hasIntroduced = false

  init(text: String, isStreaming: Bool = false, messageID: UUID? = nil) {
    self.text = text
    self.isStreaming = isStreaming
    self.messageID = messageID
    let introducesReply = isStreaming && messageID.map { !AIResponseIntroductionRegistry.contains($0) } == true
    _introductionProgress = State(initialValue: introducesReply ? 0 : 1)
  }

  var body: some View {
    let response = cache.response(for: text, isStreaming: isStreaming)
    let hasContent = !response.markdown.isEmpty || response.interface != nil
    VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
      StreamingMarkdownView(text: response.markdown, isStreaming: isStreaming)
      if let interface = response.interface {
        NativeAIInterfaceView(interface: interface, messageID: messageID, allowsInteractions: !isStreaming)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textRenderer(TextRevealRenderer(progress: introductionProgress))
    .opacity(introductionProgress == 0 ? 0 : 1)
    .onAppear { introduceIfNeeded(hasContent: hasContent) }
    .onChange(of: hasContent) { _, hasContent in introduceIfNeeded(hasContent: hasContent) }
  }

  private func introduceIfNeeded(hasContent: Bool) {
    guard hasContent, !hasIntroduced else { return }
    hasIntroduced = true
    guard isStreaming, let messageID, AIResponseIntroductionRegistry.claim(messageID), !reduceMotion else {
      introductionProgress = 1
      return
    }
    // Only the first arriving content resolves in. Later tokens retain their
    // native arrival time and the same selectable Markdown view hierarchy.
    withAnimation(.smooth(duration: 0.36)) { introductionProgress = 1 }
  }
}
