import SwiftUI

/// A single optical treatment for symbols that represent content throughout
/// the app. Navigation symbols stay unboxed; content symbols use this badge.
struct MemoraIconBadge: View {
  var symbol: MemoraIcon
  var size: CGFloat = 36

  var body: some View {
    Image(icon: symbol, size: size * 0.42)
      .foregroundStyle(.primary)
      .frame(width: size, height: size)
      .background(MemoraPalette.selection, in: RoundedRectangle(cornerRadius: MemoraRadius.small, style: .continuous))
      .accessibilityHidden(true)
  }
}
