import SwiftUI

struct AgentPromptSuggestionsView: View {
  @Environment(MemoraModel.self) private var model
  var isComposing = false

  var body: some View {
    let suggestions = model.agentPromptSuggestions
    let showsSuggestions = !isComposing && model.composerDraft.isEmpty && model.composerAttachment == nil
    GeometryReader { proxy in
      let bottomInset = model.bottomContentClearance
      ScrollView {
        VStack(spacing: 0) {
          Spacer(minLength: MemoraSpacing.section)
          MemoraBrandMark(width: min(96, proxy.size.width * 0.26))
            .opacity(0.26)
            .accessibilityHidden(true)
          Spacer(minLength: MemoraSpacing.section)
          if showsSuggestions && !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
              ForEach(suggestions.prefix(3)) { suggestion in
                AgentPromptSuggestionRow(suggestion: suggestion) {
                  InteractionFeedback.shared.send(.selection)
                  model.stageAgentSuggestion(suggestion)
                }
                .disabled(model.isAIChatResponding)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ai.agentSuggestions")
          }
        }
        .frame(minHeight: max(0, proxy.size.height - bottomInset))
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: MemoraSpacing.messageWidth)
        .frame(maxWidth: .infinity)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }
}
