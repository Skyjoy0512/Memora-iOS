import SwiftUI

extension View {
  /// The neutral rounded surface used for cards across the app. Keeping the
  /// fill and corner style here keeps screens visually consistent.
  func memoraCard(radius: CGFloat = 20) -> some View {
    background(
      Color(uiColor: .secondarySystemBackground),
      in: RoundedRectangle(cornerRadius: radius, style: .continuous)
    )
  }
}
