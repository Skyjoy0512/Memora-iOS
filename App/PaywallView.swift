import SwiftUI

struct PaywallView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var plan = SubscriptionPlan.annual

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sparkles")
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(.primary)
              .frame(width: 60, height: 60)
              .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("会議が終わった瞬間から、\n次の仕事を始められる。")
              .font(.largeTitle.bold())
              .tracking(-0.7)
            Text("Memora Plusは、長い会議も複数の会議も、要点と行動へ途切れず整理します。")
              .font(.body)
              .foregroundStyle(.secondary)
              .lineSpacing(4)
          }

          VStack(alignment: .leading, spacing: 16) {
            BenefitRow(symbol: "infinity", title: "高度なAI整理を制限なく", detail: "要約・決定・タスク・未決事項まで")
            BenefitRow(symbol: "square.stack.3d.up", title: "複数会議をまとめて質問", detail: "プロジェクトや全会議から根拠付きで回答")
            BenefitRow(symbol: "icloud", title: "クラウド保存と同期", detail: "必要な人だけ選べる保存先")
            BenefitRow(symbol: "rectangle.slash", title: "広告なし", detail: "会議内容だけに集中")
          }

          Picker("プラン", selection: $plan) {
            ForEach(SubscriptionPlan.allCases) { option in
              Text(option.label).tag(option)
            }
          }
          .pickerStyle(.segmented)

          VStack(spacing: 10) {
            Button {
              dismiss()
            } label: {
              VStack(spacing: 2) {
                Text("7日間無料で試す")
                  .font(.headline)
                Text(plan.priceLine)
                  .font(.caption)
                  .opacity(0.8)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .foregroundStyle(Color(uiColor: .systemBackground))
              .background(.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("無料期間終了の24時間前までにキャンセルすれば料金はかかりません。")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }

          Button("購入を復元") {}
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
      }
      .navigationTitle("Memora Plus")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
      }
    }
  }
}

private enum SubscriptionPlan: String, CaseIterable, Identifiable {
  case annual
  case monthly

  var id: Self { self }

  var label: String {
    switch self {
    case .annual:
      "年額 · 2か月分お得"
    case .monthly:
      "月額"
    }
  }

  var priceLine: String {
    switch self {
    case .annual:
      "その後 年額 ¥8,800"
    case .monthly:
      "その後 月額 ¥880"
    }
  }
}

private struct BenefitRow: View {
  var symbol: String
  var title: String
  var detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(width: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}
