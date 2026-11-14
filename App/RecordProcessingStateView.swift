import SwiftUI

/// Waiting and recovery use the same reading hierarchy without a separate card.
struct RecordProcessingStateView: View {
  var title: String
  var message = ""
  var actionTitle: String
  var action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Text(title)
        .font(MemoraTypography.body.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
      if !message.isEmpty {
        Text(message)
          .font(MemoraTypography.secondary)
          .foregroundStyle(MemoraPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Button(actionTitle, action: action)
        .buttonStyle(MemoraButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
