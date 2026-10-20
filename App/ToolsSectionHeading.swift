import SwiftUI

struct ToolsSectionHeading: View {
  var title: String

  var body: some View {
    Text(title)
      .font(MemoraTypography.sectionHeading)
      .foregroundStyle(MemoraPalette.textPrimary)
      .textCase(nil)
      .padding(.top, MemoraSpacing.md)
      .padding(.bottom, MemoraSpacing.sm)
      .accessibilityAddTraits(.isHeader)
  }
}
