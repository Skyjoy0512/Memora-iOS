import SwiftUI

/// The colored tile beside a settings row, as in the system Settings app, so
/// each row can be found by its color and shape before reading it.
struct SettingsIcon: View {
  var icon: MemoraIcon
  var color: Color
  /// Shrinks a glyph that reads heavier than its neighbours (three people,
  /// say), so every tile looks the same weight.
  var glyphScale: CGFloat = 1
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29

  var body: some View {
    Image(icon: icon, size: size)
      .font(.system(size: size * 0.58 * glyphScale, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
      .accessibilityHidden(true)
  }
}
