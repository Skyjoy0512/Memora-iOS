import SwiftUI

struct PaywallView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var selectedPlan: MemoraPlan = .pro
  @State private var isUnavailableNoticePresented = false
  @State private var isLicensePresented = false
  @State private var savedLocalPlan: MemoraPlan?

  var body: some View {
    NavigationStack {
      MemoraForm {
        Section {
          Text("プランを確認")
            .font(MemoraTypography.screenTitle)
            .accessibilityAddTraits(.isHeader)
          Text("購入とMemora Intelligenceは準備中です。プランを選んでも課金されません。")
            .foregroundStyle(.secondary)
        }
        Section {
          Picker("プラン", selection: $selectedPlan) {
            ForEach(MemoraPlan.allCases) { plan in
              Text(plan.label).tag(plan)
            }
          }
          .pickerStyle(.menu)
          .accessibilityIdentifier("plan.selection")
          LabeledContent("月額（予定）", value: selectedPlan.priceLabel)
          LabeledContent("AIクレジット（予定）", value: "\(selectedPlan.monthlyCredits.formatted()) / 月")
          if selectedPlan.includesTeam {
            Text("チームワークスペースは準備中です。クレジットは1人ごとの上限です。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          if selectedPlan == .unlimited || selectedPlan == .team {
            Text("Memora Intelligenceには月間上限があります。クラウドAIが無制限になるプランではありません。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("提供予定のプラン")
        } footer: {
          Text("予定価格とクレジットは未提供の内容です。現在は購入・復元・クレジットの利用はできません。")
        }
        Section {
          Text("録音と端末内の文字起こし")
          Text("対応端末のAI、または自分のAPIキーを使った要約・Ask AI")
        } header: {
          Text("いま利用できること")
        } footer: {
          Text("BYOKの利用料は各プロバイダーから請求されます。プラン変更で外部APIが無料にはなりません。")
        }
        Section {
          LabeledContent("この端末の設定", value: model.plan?.label ?? "無料")
          if model.activeLicense != nil {
            Text("法人ライセンスの利用権限が優先されます。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Button(model.plan == selectedPlan ? "この端末で選択済み" : "\(selectedPlan.label)を端末の設定として選ぶ") {
            model.choosePlan(selectedPlan)
            savedLocalPlan = selectedPlan
            model.announce("この端末の設定を更新しました。")
          }
          .disabled(model.plan == selectedPlan)
          .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget)
          .accessibilityIdentifier("plan.chooseLocal")
          if savedLocalPlan == selectedPlan, model.plan == selectedPlan {
            Text("この端末の設定を更新しました。")
              .font(.footnote)
              .foregroundStyle(MemoraPalette.textSecondary)
          }
        } footer: {
          Text("ローカルな設定です。有効な購入やサブスクリプションを示すものではありません。")
        }
        Section {
          Button("購入の復元について") { isUnavailableNoticePresented = true }
            .frame(minHeight: MemoraSpacing.touchTarget)
          Button("法人ライセンスコードを入力") { isLicensePresented = true }
            .frame(minHeight: MemoraSpacing.touchTarget)
          #if DEBUG
          Button("無料プランに戻す", role: .destructive) { model.choosePlan(nil) }
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
      .onAppear { selectedPlan = model.effectivePlan ?? .pro }
      .sheet(isPresented: $isLicensePresented) {
        NavigationStack { LicenseActivationView() }
      }
      .alert("購入・復元は準備中です", isPresented: $isUnavailableNoticePresented) {
        Button("閉じる", role: .cancel) {}
      } message: {
        Text("StoreKitは未接続です。端末のプラン設定による課金はありません。Memora Intelligenceとチームワークスペースは利用可能になりません。")
      }
    }
  }
}
