import SwiftUI

struct ImportProgressOverlay: View {
  var progress: Double

  var body: some View {
    ZStack {
      Color.black.opacity(0.22)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(.primary)

        VStack(spacing: 4) {
          Text("音声を取り込んでいます")
            .font(.headline)
          Text("完了すると文字起こしが自動で始まります")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }
      .padding(24)
      .frame(maxWidth: 310)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("音声を取り込み中、\(Int(progress * 100))パーセント")
  }
}
