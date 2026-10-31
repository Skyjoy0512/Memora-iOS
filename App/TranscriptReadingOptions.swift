import SwiftUI

struct TranscriptReadingOptions: View {
  @Binding var isReadable: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Toggle("読みやすく表示", isOn: $isReadable)
        .frame(minHeight: MemoraSpacing.touchTarget)
        .accessibilityIdentifier("transcript.readable")
    }
  }
}
