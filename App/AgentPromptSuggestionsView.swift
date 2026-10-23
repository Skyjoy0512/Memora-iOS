import SwiftUI

struct AgentPromptSuggestionsView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    let suggestions = model.agentPromptSuggestions
    ScrollView {
      if !suggestions.isEmpty {
        VStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
          VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
            Text("あなたのAIエージェント")
              .font(.title2.weight(.semibold))
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("ai.agentSuggestions")
            Text("整理から、次のアクションまで。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
              AgentPromptSuggestionRow(suggestion: suggestion) {
                InteractionFeedback.shared.send(.selection)
                model.stageAgentSuggestion(suggestion)
              }
              .disabled(!model.composerDraft.isEmpty || model.composerAttachment != nil || model.isAIChatResponding)
            }
          }
          Text(model.composerDraft.isEmpty && model.composerAttachment == nil
            ? "提案は入力欄で編集できます。保存や外部操作には確認が必要です。"
            : "入力中の内容を優先しています。新しい提案は、下書きや添付を送信または消去した後に選べます。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MemoraSpacing.screen)
        .padding(.top, MemoraSpacing.group)
        .padding(.bottom, MemoraSpacing.xxl)
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .scrollDismissesKeyboard(.interactively)
  }
}
