import SwiftUI

/// A single optical treatment for symbols that represent content throughout
/// the app. Navigation symbols stay unboxed; content symbols use this badge.
struct MemoraIconBadge: View {
  var symbol: String
  var size: CGFloat = 36

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.4, weight: .medium))
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(.primary)
      .frame(width: size, height: size)
      .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
      .accessibilityHidden(true)
  }
}
