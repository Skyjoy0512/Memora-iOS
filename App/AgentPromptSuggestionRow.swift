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
      HStack(spacing: 8) {
        Image(icon: icon, size: 20).accessibilityHidden(true)
        Text(suggestion.title).font(.body)
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(MemoraPalette.textSecondary)
      .padding(.horizontal, 14).padding(.vertical, 10)
      .frame(minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .background(MemoraPalette.card, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .accessibilityValue(suggestion.sourceTitle ?? "")
    .accessibilityHint("入力欄に提案を入れます。自動では送信しません。")
    .accessibilityIdentifier("ai.suggestion.\(suggestion.id)")
  }
}
