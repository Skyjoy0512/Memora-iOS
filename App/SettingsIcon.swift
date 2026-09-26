import SwiftUI

/// The colored tile beside a settings row, as in the system Settings app, so
/// each row can be found by its color and shape before reading it.
struct SettingsIcon: View {
  var icon: MemoraIcon
  var color: Color
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29

  var body: some View {
    Image(icon: icon)
      .resizable()
      .scaledToFit()
      .frame(width: size * 0.64, height: size * 0.64)
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
      .accessibilityHidden(true)
  }
}
