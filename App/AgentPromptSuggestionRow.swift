import SwiftUI

struct AgentPromptSuggestionRow: View {
  var suggestion: AgentPromptSuggestion
  var onSelect: () -> Void

  private var icon: MemoraIcon {
    switch suggestion.kind {
    case .tasks, .priorities: .checkmarkSquare
    case .mail: .envelope
    case .document: .docRichtext
    }
  }

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: MemoraSpacing.md) {
        Image(icon: icon, size: 18)
          .foregroundStyle(MemoraPalette.textSecondary)
          .accessibilityHidden(true)
        Text(suggestion.title).font(.subheadline)
          .foregroundStyle(MemoraPalette.textPrimary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Image(icon: .chevronRight, size: 12)
          .foregroundStyle(MemoraPalette.textSecondary)
          .accessibilityHidden(true)
      }
      .padding(.vertical, MemoraSpacing.sm)
      .frame(minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .accessibilityValue(suggestion.sourceTitle ?? "")
    .accessibilityHint("入力欄に提案を入れます。自動では送信しません。")
    .accessibilityIdentifier("ai.suggestion.\(suggestion.id)")
  }
}
