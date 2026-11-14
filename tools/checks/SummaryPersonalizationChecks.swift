import Foundation

@main
struct SummaryPersonalizationChecks {
  static func main() {
    for (text, expected) in [
      ("毛先を3cmくらい切りたいです。前髪は短くしたくないです。次回はカラーも相談したいです", "work.customer-chart"),
      ("来月のスタッフ配置を決めます。土曜日は2人体制にします", "market.regular"),
      ("午後の移動介助を実施しました。腰の痛みを訴えていました。明日の担当者にも共有してください", "work.shift-handover"),
      ("今日は3階の配管工事を行った。部材が不足した。明日は追加部材を使用する", "work.daily"),
      ("今日は公園に行った。天気が良くて楽しかった", "work.journal")
    ] {
      precondition(SummaryTemplateSelector.contentTemplateID(text) == expected)
    }
    precondition(SummaryTemplateSelector.contentTemplateID("はい、確認します") == nil)
    let sections = SummarySection.parse("# 記録\n概要\n## 希望\n- 短くしたい\n## 提案\n- 次回相談\n### 補足\n原文確認")
    precondition(sections.count == 2 && sections[1].order == 1)
    precondition(sections[0].content == "- 短くしたい")
    precondition(sections[1].content.contains("### 補足"))
    precondition(sections.allSatisfy { $0.sourceReferences.isEmpty })
    let parsed = SummaryResponseParser.parse("## 希望\n短くしたい\n<memora-data>{\"templateID\":\"work.customer-chart\",\"actions\":[]}</memora-data>")
    precondition(parsed.templateID == "work.customer-chart" && !parsed.markdown.contains("memora-data"))
    precondition(SummaryResponseParser.parse("旧形式の要約").templateID == nil)
    let valid = SummaryResponseParser.validateTemplate(parsed, allowedIDs: ["work.customer-chart"], actionFreeIDs: ["work.customer-chart"])
    precondition(valid.templateID == "work.customer-chart" && valid.actions.isEmpty)
    let invalid = SummaryResponseParser.validateTemplate(parsed, allowedIDs: ["work.journal"], actionFreeIDs: [])
    precondition(invalid.templateID == nil && invalid.actions.isEmpty)
    let missing = SummaryResponseParser.validateTemplate(SummaryResponseParser.parse("旧形式の要約"),
      allowedIDs: ["work.journal"], actionFreeIDs: [])
    precondition(missing.templateID == nil)
    let emptyActions = SummaryResponseParser.parse("## アクションアイテム\n- [ ] 実行する\n<memora-data>{\"actions\":[]}</memora-data>")
    precondition(emptyActions.actions.isEmpty)
    let generics = ["overview", "minutes", "journal", "actions"]
    let candidates = SummaryTemplateSelector.candidateIDs(fallbackID: "manual", contentID: "private",
      recommendedIDs: (0..<30).map { "work\($0)" }, genericIDs: generics,
      availableIDs: Set(generics + ["manual", "private"] + (0..<30).map { "work\($0)" }))
    precondition(candidates.count == 8 && Set(generics + ["manual", "private"]).isSubset(of: Set(candidates)))
    precondition(Set(candidates).count == candidates.count)
    let adaptiveCandidates = SummaryTemplateSelector.candidateIDs(fallbackID: "content.adaptive", contentID: "market.regular",
      recommendedIDs: ["market.sales"], genericIDs: ["work.learning", "work.journal"],
      availableIDs: ["content.adaptive", "market.regular", "market.sales", "work.learning", "work.journal"])
    precondition(adaptiveCandidates.first == "content.adaptive" && Set(adaptiveCandidates).count == 5)
    print("SummaryPersonalizationChecks: passed (content scenarios, sections, output compatibility)")
  }
}
