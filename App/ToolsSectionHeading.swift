import SwiftUI

struct ToolsSectionHeading: View {
  var title: String

  var body: some View {
    Text(title)
      .font(.title3.weight(.semibold))
      .foregroundStyle(MemoraPalette.textPrimary)
      .textCase(nil)
      .padding(.top, MemoraSpacing.xxl)
      .padding(.bottom, MemoraSpacing.md)
      .accessibilityAddTraits(.isHeader)
  }
}
