import SwiftUI

/// A document the agent made in this reply. Tapping opens it.
struct AgentDocumentCard: View {
  var document: MemoraDocument
  var open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(spacing: 12) {
        DocumentRow(document: document, spaceName: nil)
        Spacer(minLength: 4)
        Image(icon: .chevronRight, size: 12)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, MemoraSpacing.md)
      .padding(.vertical, MemoraSpacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityHint("\(document.kind.label)を開きます")
  }
}
