import SwiftUI

struct ToolbarIconGlyph: View {
  var icon: MemoraIcon

  var body: some View {
    Image(icon: icon, size: MemoraIconMetrics.glyph)
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(MemoraPalette.textPrimary)
      .accessibilityHidden(true)
  }
}
