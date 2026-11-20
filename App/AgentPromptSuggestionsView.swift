import SwiftUI

struct AgentPromptSuggestionsView: View {
  @Environment(MemoraModel.self) private var model
  var isComposing = false

  var body: some View {
    let suggestions = model.agentPromptSuggestions
    GeometryReader { proxy in
      ZStack {
        MemoraBrandMark(width: min(190, proxy.size.width * 0.46))
          .opacity(0.10)
          .accessibilityHidden(true)
          .position(x: proxy.size.width / 2,
            y: max(32, proxy.size.height / 2 - 32))
        if !isComposing && model.composerDraft.isEmpty && model.composerAttachment == nil {
          ScrollView {
            VStack(alignment: .leading, spacing: MemoraSpacing.md) {
              ForEach(suggestions.prefix(3)) { suggestion in
                AgentPromptSuggestionRow(suggestion: suggestion) {
                  InteractionFeedback.shared.send(.selection)
                  model.stageAgentSuggestion(suggestion)
                }
                .disabled(model.isAIChatResponding)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MemoraSpacing.lg).padding(.top, 12)
            .padding(.bottom, model.bottomContentClearance)
          }
          .scrollBounceBehavior(.basedOnSize)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: MemoraSpacing.readingWidth)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .accessibilityIdentifier("ai.agentSuggestions")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
