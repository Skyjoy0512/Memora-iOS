import SwiftUI

struct ToolbarIconGlyph: View {
  var icon: MemoraIcon

  var body: some View {
    Image(icon: icon, size: MemoraIconMetrics.glyph)
      .foregroundStyle(MemoraPalette.textPrimary)
      .accessibilityHidden(true)
  }
}
