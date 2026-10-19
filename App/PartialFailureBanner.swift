import SwiftUI

struct PartialFailureBanner: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("文字起こしは使えます", icon: .exclamationmarkTriangleFill)
        .font(.headline)
        .foregroundStyle(MemoraPalette.warning)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("AI整理だけ再試行", icon: .arrowClockwise, action: retry)
        .font(.subheadline.weight(.semibold))
    }
    .padding(MemoraSpacing.lg)
    .memoraCard()
  }
}
