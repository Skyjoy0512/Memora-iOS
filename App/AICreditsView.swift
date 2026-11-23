import SwiftUI

/// What AI credits are, how many are left, and what things cost, so a limit is
/// never a surprise.
struct AICreditsView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    MemoraForm {
      Section {
        LabeledContent("プラン", value: model.planName)
        LabeledContent("利用状況", value: model.memoraCreditStatus)
        LabeledContent("文字起こし", value: "端末内（無制限）")
      } header: {
        Text("利用状況")
          .accessibilityAddTraits(.isHeader)
      } footer: {
        if let blocker = model.memoraIntelligenceBlocker {
          Text(blocker)
        } else {
          Text("利用すると残高が更新されます。")
        }
      }

      Section {
        ForEach(MemoraIntelligence.typicalCosts, id: \.action) { cost in
          LabeledContent(cost.action, value: "\(cost.credits)クレジット")
        }
      } header: {
        Text(MemoraIntelligence.isConfigured ? "使うクレジットの目安" : "提供予定のクレジットの目安")
      } footer: {
        Text("端末内AIと自分のAPIキーではMemoraのクレジットを使いません。API利用料は提供元の条件に従います。")
      }

      Section {
        Button("プランを見る") { model.isPaywallPresented = true }
      }
    }
    .navigationTitle("AIクレジット")
    .navigationBarTitleDisplayMode(.inline)
  }
}
