import SwiftUI

struct SettingsPlanCard: View {
  var onOpenPlan: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Memoraでもっと活用")
        .font(.headline)
      Text("プランやAIクレジットの内容を確認できます。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button("プランを見る", action: onOpenPlan)
      .buttonStyle(MemoraButtonStyle())
      .padding(.top, MemoraSpacing.xs)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MemoraSpacing.card)
    .memoraCard()
  }
}
