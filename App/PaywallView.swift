import SwiftUI

struct PaywallView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var selectedPlan: MemoraPlan = .pro
  @State private var isUnavailableNoticePresented = false
  @State private var isLicensePresented = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 12) {
            Image(icon: selectedPlan.symbol, size: 30)
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(.primary)
              .frame(width: 60, height: 60)
              .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
              .accessibilityHidden(true)
              .contentTransition(.symbolEffect(.replace))
            Text(selectedPlan.tagline)
              .font(.largeTitle.bold())
              .tracking(-0.7)
            Text("現在は、対応端末の端末内AIと、自分のAPIキー（BYOK）を設定したクラウドAIを利用できます。Memora Intelligenceと購入は準備中です。BYOKの利用料は各プロバイダーから請求されます。")
              .font(.body)
              .foregroundStyle(.secondary)
              .lineSpacing(4)
          }

          MemoraSectionPicker(items: MemoraPlan.allCases, selection: $selectedPlan, title: \.label)

          VStack(alignment: .leading, spacing: 4) {
            Text(selectedPlan.priceLabel)
              .font(.title.bold())
              .contentTransition(.numericText())
            Text("年額は月額の10か月分")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 16) {
            ForEach(selectedPlan.features, id: \.self) { feature in
              BenefitRow(symbol: .checkmarkCircleFill, title: feature, detail: nil)
            }
          }

          if model.plan == selectedPlan {
            currentPlanFooter
          } else {
            purchaseControls
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .padding(.bottom, 12)
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("プラン")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .onAppear { selectedPlan = model.effectivePlan ?? .pro }
      .animation(reduceMotion ? nil : MemoraMotion.control, value: selectedPlan)
      .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.plan)
      .sheet(isPresented: $isLicensePresented) {
        NavigationStack { LicenseActivationView() }
      }
      .alert("購入はまだ接続されていません", isPresented: $isUnavailableNoticePresented) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("StoreKitによる購入・復元はまだ実装されていません。選んだプランは、この端末で機能を試すためのローカルな設定として保存します。")
      }
    }
  }

  private var purchaseControls: some View {
    VStack(spacing: 12) {
      Button(action: choose) {
        VStack(spacing: 2) {
          Text("\(selectedPlan.label)にする")
            .font(.headline)
          Text("購入は準備中 · いまは端末の設定として切り替えます")
            .font(.caption)
            .opacity(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(.white)
        .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .buttonStyle(.plain)

      Text("購入・復元は未接続です。表示価格とAIクレジットは提供予定のプラン内容で、端末でのプラン変更による課金は発生しません。")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)

      Button("購入を復元") {
        isUnavailableNoticePresented = true
      }
      .font(.footnote)
      .frame(maxWidth: .infinity)

      Button("法人のライセンスコードをお持ちの方", icon: .building2Fill) {
        isLicensePresented = true
      }
      .font(.footnote)
      .frame(maxWidth: .infinity)

      #if DEBUG
      Button("無料プランに戻す", role: .destructive) {
        model.choosePlan(nil)
        selectedPlan = .pro
      }
      .font(.footnote)
      #endif
    }
  }

  private var currentPlanFooter: some View {
    VStack(spacing: 12) {
      Label("\(selectedPlan.label)を利用中", icon: .checkmarkSealFill)
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

      Text("購入は未接続のため、この端末での設定です。課金の接続後は、App Storeのサブスクリプション設定から変更・解約できるようにします。")
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

  /// There is no StoreKit behind this yet, so choosing a plan explains that it
  /// is a local setting rather than pretending a purchase happened.
  private func choose() {
    model.choosePlan(selectedPlan)
    isUnavailableNoticePresented = true
  }
}

private struct BenefitRow: View {
  var symbol: MemoraIcon
  var title: String
  var detail: String?

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(icon: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(width: 30)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        if let detail {
          Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
