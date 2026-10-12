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
        Image(icon: .chevronRight)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MemoraPalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityHint("\(document.kind.label)を開きます")
  }
}
