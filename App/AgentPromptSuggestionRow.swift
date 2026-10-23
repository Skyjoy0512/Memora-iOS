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
      HStack(alignment: .top, spacing: MemoraSpacing.md) {
        MemoraInterfaceIcon(icon: icon)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
          Text(suggestion.title).font(.body.weight(.medium))
          if let title = suggestion.sourceTitle {
            Text(title).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
          } else {
            Text("参照できる記録を選んで開始")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
          .padding(.top, MemoraSpacing.xs)
          .accessibilityHidden(true)
      }
      .foregroundStyle(MemoraPalette.textPrimary)
      .padding(.vertical, MemoraSpacing.lg)
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(MemoraQuietButtonStyle())
    .accessibilityHint("入力欄に提案を入れます。自動では送信しません。")
    .accessibilityIdentifier("ai.suggestion.\(suggestion.id)")
  }
}
