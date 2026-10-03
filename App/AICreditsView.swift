import SwiftUI

/// What AI credits are, how many are left, and what things cost, so a limit is
/// never a surprise.
struct AICreditsView: View {
  @Environment(MemoraModel.self) private var model
  @State private var meter = MemoraCreditMeter.shared

  var body: some View {
    List {
      Section {
        LabeledContent("プラン", value: model.planName)
        LabeledContent("今月のクレジット", value: model.effectivePlan.map { "\($0.monthlyCredits.formatted())" } ?? "なし")
        LabeledContent("残り") {
          if let remaining = meter.remaining {
            Text("\(remaining.formatted())")
          } else {
            Text("まだ使っていません").foregroundStyle(.secondary)
          }
        }
        if let plan = model.effectivePlan, plan.cloudTranscriptionHours > 0 {
          LabeledContent("クラウド文字起こし", value: "\(plan.cloudTranscriptionHours)時間/月")
        }
      } footer: {
        if let blocker = model.memoraIntelligenceBlocker {
          Text(blocker)
        } else {
          Text("残りはMemora Intelligenceを使ったときに更新されます。毎月1日に戻ります。")
        }
      }

      Section {
        ForEach(MemoraIntelligence.typicalCosts, id: \.action) { cost in
          LabeledContent(cost.action, value: "\(cost.credits)クレジット")
        }
      } header: {
        Text("使うクレジットの目安")
      } footer: {
        Text("実際に使った量で引かれます。長い会議ほど多く、短い質問ほど少なくなります。端末内AIと自分のAPIキー（BYOK）ではクレジットを使いません。")
      }

      Section {
        Button("プランを見る") { model.isPaywallPresented = true }
      }
    }
    .navigationTitle("AIクレジット")
    .navigationBarTitleDisplayMode(.inline)
  }
}
