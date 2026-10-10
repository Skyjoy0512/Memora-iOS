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
      Button(action: onOpenPlan) {
        Text("プランを見る")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color(uiColor: .systemBackground))
          .padding(.horizontal, 18)
          .frame(minHeight: 44)
          .background(Color.primary, in: Capsule())
      }
      .buttonStyle(.plain)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
  }
}
