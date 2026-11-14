import SwiftUI

struct AgentPromptSuggestionsView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    let suggestions = model.agentPromptSuggestions
    ScrollView {
      if !suggestions.isEmpty {
        VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
          VStack(spacing: 0) {
            ForEach(suggestions.prefix(3)) { suggestion in
              AgentPromptSuggestionRow(suggestion: suggestion) {
                InteractionFeedback.shared.send(.selection)
                model.stageAgentSuggestion(suggestion)
              }
              .disabled(!model.composerDraft.isEmpty || model.composerAttachment != nil || model.isAIChatResponding)
            }
          }
          if !model.composerDraft.isEmpty || model.composerAttachment != nil {
            Text("入力中の内容を送信または消去すると、提案を選べます。")
              .font(.footnote)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.group)
        .padding(.bottom, MemoraSpacing.xxl)
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("ai.agentSuggestions")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .scrollDismissesKeyboard(.interactively)
  }
}
