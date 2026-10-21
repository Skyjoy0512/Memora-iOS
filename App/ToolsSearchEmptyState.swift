import SwiftUI

/// Keep search guidance above the keyboard, without a full-height empty canvas.
struct ToolsSearchEmptyState: View {
  var body: some View {
    VStack(spacing: MemoraSpacing.sm) {
      Text("見つかりません").font(.headline)
      Text("検索語を変えるか、別の分類を選んでください。")
        .font(.subheadline).foregroundStyle(MemoraPalette.textSecondary)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.top, MemoraSpacing.section)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("tools.empty")
  }
}
