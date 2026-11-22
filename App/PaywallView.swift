import SwiftUI

struct PaywallView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var selectedPlan: MemoraPlan?
  @State private var isLicensePresented = false
  @State private var savedLocalPlan: MemoraPlan?

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Text("購入・復元は準備中です。端末の設定を変えても課金されません。")
            .foregroundStyle(.secondary)
        }
        Section {
          Text("録音と端末内の文字起こし")
          Text("対応端末のAI、または自分のAPIキーを使った要約・Ask AI")
        } header: {
          Text("いま利用できること")
        } footer: {
          Text("自分のAPIキーではMemoraのクレジットを使いません。API利用料は提供元の条件に従います。")
        }
        Section {
          ForEach(MemoraPlan.allCases) { plan in
            planRow(plan)
          }
        } header: {
          Text("提供予定のプラン")
        } footer: {
          Text("AIクレジットには月間上限があります。チームの上限は1人ごとです。")
        }
        Section {
          LabeledContent("この端末の設定", value: model.plan?.label ?? "無料")
            .accessibilityIdentifier("plan.saved")
          if let license = model.activeLicense {
            LabeledContent("適用中の法人ライセンス", value: "\(license.plan.label)（\(license.company)）")
          }
          Button("この端末の設定に保存") {
            guard let selectedPlan else { return }
            model.choosePlan(selectedPlan)
            savedLocalPlan = selectedPlan
            model.announce("この端末の設定を更新しました。")
          }
          .disabled(selectedPlan == nil || model.plan == selectedPlan)
          .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
          .accessibilityIdentifier("plan.chooseLocal")
          if let savedLocalPlan, savedLocalPlan == selectedPlan, model.plan == selectedPlan {
            Text("この端末の設定を更新しました。")
              .font(.footnote)
              .foregroundStyle(MemoraPalette.textSecondary)
          }
        }
        Section {
          Button("法人ライセンスコードを入力") { isLicensePresented = true }
            .frame(minHeight: MemoraSpacing.touchTarget)
          #if DEBUG
          Button("無料プランに戻す", role: .destructive) {
            model.choosePlan(nil)
            selectedPlan = nil
            savedLocalPlan = nil
          }
          .frame(minHeight: MemoraSpacing.touchTarget)
          #endif
        }
      }
      .navigationTitle("プラン")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          ToolbarIconButton("閉じる", icon: .xmark) { dismiss() }
        }
      }
      .onAppear { selectedPlan = model.plan }
      .sheet(isPresented: $isLicensePresented) {
        NavigationStack { LicenseActivationView() }
      }
    }
  }

  private func planRow(_ plan: MemoraPlan) -> some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: MemoraSpacing.md))
    let isSelected = selectedPlan == plan
    return Button {
      selectedPlan = plan
    } label: {
      HStack(spacing: MemoraSpacing.sm) {
        layout {
          Text(plan.label)
            .font(MemoraTypography.body.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: MemoraSpacing.xs) {
            Text(plan.priceLabel)
              .monospacedDigit()
            Text("\(plan.monthlyCredits.formatted()) AIクレジット/月")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        Image(icon: .checkmark, size: 16)
          .opacity(isSelected ? 1 : 0)
          .accessibilityHidden(true)
      }
      .frame(minHeight: MemoraSpacing.touchTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier("plan.option.\(plan.rawValue)")
  }
}
