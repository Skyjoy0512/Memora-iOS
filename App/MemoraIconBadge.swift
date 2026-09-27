import SwiftUI

/// A single optical treatment for symbols that represent content throughout
/// the app. Navigation symbols stay unboxed; content symbols use this badge.
struct MemoraIconBadge: View {
  var symbol: MemoraIcon
  var size: CGFloat = 36

  var body: some View {
    Image(icon: symbol)
      .resizable()
      .scaledToFit()
      .frame(width: size * 0.5, height: size * 0.5)
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(.primary)
      .frame(width: size, height: size)
      .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
      .accessibilityHidden(true)
  }
}
