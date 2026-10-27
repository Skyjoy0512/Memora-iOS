import SwiftUI

struct PresentationPlanFields: View {
  @Binding var plan: PresentationPlan
  var slides: [DocumentSlide]

  var body: some View {
    Form {
      Section("目的と対象読者") {
        LabeledContent("目的") { TextField("何を伝える資料か", text: $plan.purpose, axis: .vertical) }
        LabeledContent("対象読者") { TextField("誰に見せるか", text: $plan.audience, axis: .vertical) }
        LabeledContent("判断事項") { TextField("何を判断してほしいか", text: $plan.decision, axis: .vertical) }
      }
      Section {
        TextField("未確認の前提（1行に1件）", text: $plan.assumptionsText, axis: .vertical)
      } header: { Text("未確認事項") } footer: {
        Text("安全に推定した条件も、確認済みの事実と分けて残します。")
      }
      Section {
        ForEach($plan.storyline) { $point in
          PresentationStoryPointFields(point: $point)
        }
        Button("未設定のスライドを構成に追加") {
          let ids = Set(plan.storyline.map(\.slideID))
          plan.storyline += slides.filter { !ids.contains($0.id) }.map {
            .init(slideID: $0.id, claim: $0.title.isEmpty ? "主張を入力" : $0.title)
          }
        }
      } header: { Text("ページ間のストーリー") } footer: {
        Text("結論→根拠→判断の順序と、1枚1メッセージを確認します。ここに書いた出典名だけで情報へのアクセス権限は増えません。")
      }
    }
    .navigationTitle("目的と構成")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct PresentationStoryPointFields: View {
  @Binding var point: PresentationPlan.Point

  var body: some View {
    DisclosureGroup(point.claim.isEmpty ? "主張を入力" : point.claim) {
      LabeledContent("主張") { TextField("このページの主張", text: $point.claim, axis: .vertical) }
      LabeledContent("根拠") { TextField("根拠・参照箇所（1行に1件）", text: $point.evidenceText, axis: .vertical) }
      LabeledContent("未確認") { TextField("未確認事項（1行に1件）", text: $point.unconfirmedText, axis: .vertical) }
    }
  }
}

private extension PresentationPlan {
  var assumptionsText: String {
    get { assumptions.joined(separator: "\n") }
    set { assumptions = newValue.components(separatedBy: .newlines).filter { !$0.isEmpty } }
  }
}

private extension PresentationPlan.Point {
  var evidenceText: String {
    get { evidence.joined(separator: "\n") }
    set { evidence = newValue.components(separatedBy: .newlines).filter { !$0.isEmpty } }
  }
  var unconfirmedText: String {
    get { unconfirmed.joined(separator: "\n") }
    set { unconfirmed = newValue.components(separatedBy: .newlines).filter { !$0.isEmpty } }
  }
}
