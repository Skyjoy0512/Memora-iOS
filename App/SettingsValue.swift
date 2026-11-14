import SwiftUI

struct SettingsValue: View {
  var title: String
  var value: String
  var icon: MemoraIcon

  var body: some View {
    LabeledContent {
      Text(value)
        .font(MemoraTypography.secondary)
        .foregroundStyle(MemoraPalette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    } label: {
      SettingsLabel(title, icon: icon)
    }
  }
}
