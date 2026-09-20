import SwiftUI

struct PartialFailureBanner: View {
  var message: String
  var retry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("文字起こしは使えます", systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("AI整理だけ再試行", systemImage: "arrow.clockwise", action: retry)
        .font(.subheadline.weight(.semibold))
    }
    .padding(16)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

