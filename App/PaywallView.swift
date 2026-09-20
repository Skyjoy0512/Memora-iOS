import SwiftUI

struct PaywallView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var plan = SubscriptionPlan.annual
  @State private var isUnavailableNoticePresented = false

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
              .accessibilityHidden(true)
            Text("会議が終わった瞬間から、\n次の仕事を始められる。")
              .font(.largeTitle.bold())
              .tracking(-0.7)
            Text("Memora Plusは、長い会議も複数の会議も、要点と行動へ途切れず整理します。")
              .font(.body)
              .foregroundStyle(.secondary)
              .lineSpacing(4)
          }
          .memoraAppear()

          VStack(alignment: .leading, spacing: 16) {
            BenefitRow(symbol: "infinity", title: "高度なAI整理を制限なく", detail: "要約・決定・タスク・未決事項まで")
            BenefitRow(symbol: "square.stack.3d.up", title: "複数会議をまとめて質問", detail: "プロジェクトや全会議から根拠付きで回答")
            BenefitRow(symbol: "icloud", title: "クラウド保存と同期", detail: "必要な人だけ選べる保存先")
            BenefitRow(symbol: "rectangle.slash", title: "広告なし", detail: "会議内容だけに集中")
          }
          .memoraAppear(delay: 0.06)

          if model.isSubscribed {
            subscribedFooter
              .memoraAppear(delay: 0.12)
          } else {
            purchaseControls
              .memoraAppear(delay: 0.12)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .padding(.bottom, 12)
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("Memora Plus")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
      }
      .animation(reduceMotion ? nil : MemoraMotion.control, value: plan)
      .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.isSubscribed)
      .alert("購入はまだ接続されていません", isPresented: $isUnavailableNoticePresented) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("この画面はプランの説明のみです。StoreKitによる購入・復元はまだ実装されていません。")
      }
    }
  }

  private var purchaseControls: some View {
    VStack(spacing: 18) {
      Picker("プラン", selection: $plan) {
        ForEach(SubscriptionPlan.allCases) { option in
          Text(option.label).tag(option)
        }
      }
      .pickerStyle(.segmented)

      VStack(spacing: 10) {
        Button(action: purchase) {
          VStack(spacing: 2) {
            Text("購入は準備中")
              .font(.headline)
            Text(plan.priceLine)
              .font(.caption)
              .opacity(0.8)
              .contentTransition(.numericText())
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .foregroundStyle(Color(uiColor: .systemBackground))
          .background(.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)

        Text("購入・無料期間・復元はまだ接続されていません。")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }

      Button("購入を復元") {
        isUnavailableNoticePresented = true
      }
      .font(.footnote)
      .frame(maxWidth: .infinity)
    }
  }

  private var subscribedFooter: some View {
    VStack(spacing: 12) {
      Label("Memora Plusを利用中", systemImage: "checkmark.seal.fill")
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

      Text("プランの変更と解約は、App Storeのサブスクリプション設定から行えます。")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)

      Button("続ける") { dismiss() }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
    .transition(.opacity)
  }

  /// There is no StoreKit behind this yet, so pressing purchase explains that
  /// rather than flipping a local flag that would look like a real purchase.
  private func purchase() {
    isUnavailableNoticePresented = true
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
      "価格は未定（準備中）"
    case .monthly:
      "価格は未定（準備中）"
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
        .accessibilityHidden(true)
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
