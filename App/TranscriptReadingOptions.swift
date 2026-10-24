import SwiftUI

struct TranscriptReadingOptions: View {
  @Binding var isReadable: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.sm) {
      Toggle("読みやすく表示", isOn: $isReadable)
        .frame(minHeight: MemoraSpacing.touchTarget)
        .accessibilityIdentifier("transcript.readable")
      Text(isReadable
        ? "文頭の明確なフィラーと余白だけを整えます。原文・話者・時刻は保持し、編集時は原文を開きます。"
        : "認識した原文を表示しています。本文をタップして修正できます。")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
