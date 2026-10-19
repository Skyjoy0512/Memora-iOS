import SwiftUI

/// A quiet marker on journal records the app placed on its own, so they are
/// told apart from what the person wrote or recorded.
struct AutomaticLogTag: View {
  var body: some View {
    Text("自動")
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, MemoraSpacing.sm)
      .padding(.vertical, 3)
      .background(.quaternary, in: Capsule())
      .accessibilityLabel("自動で記録")
  }
}
