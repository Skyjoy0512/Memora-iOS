import SwiftUI

/// Static native examples explain the result without pretending to record or run AI.
struct OnboardingPreview: View {
  var page: OnboardingPage
  var isCurrent: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.md) {
      Text("表示例・架空の会話")
        .font(.footnote)
        .foregroundStyle(.secondary)
      switch page {
      case .record:
        HStack(spacing: 4) {
          ForEach(0..<22, id: \.self) { index in
            Capsule()
              .fill(.primary.opacity(0.55))
              .frame(width: 3, height: barHeight(index))
          }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
        Text("「次回の会議で、提案の概算を確認しましょう。」")
          .font(.body)
      case .understand:
        Text("決まったこと").font(.headline)
        Text("次回の会議で、提案の概算を確認する。")
        Text("未決：予算・担当者").foregroundStyle(.secondary)
      case .act:
        Label("提案の概算を確認する", icon: .circle).font(.headline)
        Text("担当者・期限は未定").foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, MemoraSpacing.lg)
    .accessibilityElement(children: .combine)
  }

  private func barHeight(_ index: Int) -> CGFloat {
    let pattern: [CGFloat] = [8, 16, 24, 13, 20, 9, 26, 14]
    return pattern[index % pattern.count]
  }
}
