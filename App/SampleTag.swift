import SwiftUI

/// A quiet marker on records that came from the display samples, so they are
/// never mistaken for the person's own.
struct SampleTag: View {
  var body: some View {
    Text("サンプル")
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, MemoraSpacing.sm)
      .padding(.vertical, 3)
      .background(.quaternary, in: Capsule())
      .accessibilityLabel("サンプル")
  }
}
