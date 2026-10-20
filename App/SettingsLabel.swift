import SwiftUI

struct SettingsLabel: View {
  var title: String
  var icon: MemoraIcon

  init(_ title: String, icon: MemoraIcon) {
    self.title = title
    self.icon = icon
  }

  var body: some View {
    HStack(spacing: MemoraSpacing.md) {
      SettingsIcon(icon: icon)
      Text(title)
        .font(MemoraTypography.body)
        .foregroundStyle(MemoraPalette.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(minHeight: MemoraIconMetrics.touchTarget)
    .contentShape(Rectangle())
  }
}
