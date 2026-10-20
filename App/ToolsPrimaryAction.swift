import SwiftUI

struct ToolsPrimaryAction: View {
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.body.weight(.semibold))
        .foregroundStyle(MemoraPalette.actionLabel)
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, MemoraSpacing.lg)
        .background(MemoraPalette.action, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }
}
