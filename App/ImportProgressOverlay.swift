import SwiftUI

struct ImportProgressOverlay: View {
  /// Nil while the work cannot be measured, shown as an indeterminate bar.
  var progress: Double?

  var body: some View {
    ZStack {
      Color.black.opacity(0.22)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        if let progress {
          ProgressView(value: progress)
            .progressViewStyle(.linear)
        } else {
          ProgressView()
        }

        VStack(spacing: 4) {
          Text("取り込んでいます")
            .font(.headline)
          Text("元のファイルを残して、内容を準備します")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }
      .padding(MemoraSpacing.xxl)
      .frame(maxWidth: 310)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
      .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(progress.map { "音声を取り込み中、\(Int($0 * 100))パーセント" } ?? "音声を取り込み中")
  }
}
