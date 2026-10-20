import SwiftUI

struct ToolbarIconGlyph: View {
  var icon: MemoraIcon

  var body: some View {
    Image(icon: icon)
      .font(.system(size: MemoraIconMetrics.glyph, weight: .regular))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(MemoraPalette.textPrimary)
      .accessibilityHidden(true)
  }
}
