import SwiftUI

/// A static example keeps the introduction independent of recording and AI setup.
struct OnboardingPreview: View {
  var page: OnboardingPage

  var body: some View {
    HStack(alignment: .top, spacing: MemoraSpacing.md) {
      Image(icon: page.symbol, size: 20)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(example)
          .font(.subheadline.weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, MemoraSpacing.md)
    .accessibilityElement(children: .combine)
  }

  private var caption: String {
    switch page {
    case .record: "録音の例"
    case .understand: "要約の例"
    case .act: "タスクの例"
    }
  }

  private var example: String {
    switch page {
    case .record: "「次回の会議で見積もりを確認しましょう」"
    case .understand: "次回の会議で見積もりを確認することが決定"
    case .act: "次回の会議で見積もりを確認する"
    }
  }
}
