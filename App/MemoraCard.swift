import SwiftUI

extension View {
  /// The neutral rounded surface used for cards across the app. Keeping the
  /// fill and corner style here keeps screens visually consistent.
  func memoraCard(fill: Color = MemoraPalette.card) -> some View {
    background(
      fill,
      in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous)
    )
  }
}
