import Foundation

@main
enum MeetingSummaryPosterChecks {
  static func main() {
    let markdown = """
    ## 会議の概要
    予算は10万円ではなく12万円。承認された場合だけ来週実施する。
    ## 決定事項
    - 本番切替はしない
    - 検証環境で比較する
    - 条件は別途確認する
    ## アクションアイテム
    | タイトル | 詳細 | 担当 | 期限 |
    | --- | --- | --- | --- |
    | 予算案を確認 | 承認が前提 | 佐藤 | 来週 |
    | 結果を共有 | 否決時は延期 | 未定 | 未記載 |
    ## 未解決事項
    - 承認日は未確定
    """
    let content = MeetingSummaryPosterContent(title: "検証用会議", date: "2026/10/24", summary: markdown)
    precondition(content.sections.map(\.headings) == [["会議の概要"], ["決定事項"], ["アクションアイテム"], ["未解決事項"]])
    precondition(content.sections[0].groups[0].lines[0].text == "予算は10万円ではなく12万円。承認された場合だけ来週実施する。")
    precondition(content.sections[1].groups.map { $0.lines[0].text } == ["本番切替はしない", "検証環境で比較する", "条件は別途確認する"])
    precondition(content.sections[2].groups[0].lines.map(\.text) == ["タイトル：予算案を確認", "詳細：承認が前提", "担当：佐藤", "期限：来週"])
    precondition(!content.hasOmissions)
    precondition(content.fullSummary == markdown)
    let edited = MeetingSummaryPosterContent(title: "検証用会議", date: "2026/10/24", summary: "本文を修正しました。")
    precondition(edited != content && edited.sections.count == 1 && edited.sections[0].headings.isEmpty)
    precondition(edited.sections[0].groups[0].lines[0].text == "本文を修正しました。")
    let empty = MeetingSummaryPosterContent(title: "", date: "", summary: "")
    precondition(empty.sections.isEmpty && !empty.hasOmissions)
    let long = String(repeating: "家族👨‍👩‍👧‍👦", count: 300)
    let bounded = MeetingSummaryPosterContent(title: long, date: "", summary: "## 会議の概要\n\(long)\n## 決定事項\n- \(long)")
    precondition(bounded.title.count == 64 && bounded.sections[0].groups[0].lines[0].text.count == 320)
    precondition(bounded.fullSummary.contains(long) && bounded.hasOmissions)
    let legacy = MeetingSummaryPosterContent(title: "旧形式の検証", date: "", summary: """
    # 会議
    - **日時**: 2026/10/24
    - **用件**: 条件付きの見積確認。まだ承認はされていない。
    ## 約束したこと・決まったこと
    - 検証環境で比較する
    ## 次にやること
    - 見積を比較する
    ## まだ決まっていないこと
    - 本番への反映日
    ## 未決定事項
    - 承認者
    """)
    precondition(legacy.sections.map { $0.headings.last! } == ["会議", "約束したこと・決まったこと", "次にやること", "まだ決まっていないこと", "未決定事項"])
    precondition(legacy.sections[0].groups[1].lines[0].text == "用件: 条件付きの見積確認。まだ承認はされていない。")
    let labels = MeetingSummaryPosterContent(title: "旧形式", date: "", summary: "**日時**: 2026/10/24\n**用件**: 承認前の条件付き検討。")
    precondition(labels.sections[0].groups[0].lines[0].text == "日時: 2026/10/24 用件: 承認前の条件付き検討。")
    let unknownLabels = "**日程**: 2026/10/24\n**議題**: 条件付きで比較するが、本番切替はまだ承認されていない。"
    let literal = MeetingSummaryPosterContent(title: "旧形式", date: "", summary: unknownLabels)
    precondition(literal.sections[0].groups[0].lines[0].text == MarkdownBlockParser.plainText(unknownLabels))
    precondition(literal.sections[0].headings.isEmpty && literal.fullSummary == unknownLabels)
    let custom = MeetingSummaryPosterContent(title: "比較検討", date: "", summary: """
    ## 選択肢の比較
    ### 品質
    | 案 | 長所 | 制約 |
    | --- | --- | --- |
    | A | 低コスト | 承認が必要 |
    ## 次の実験
    - 小規模で比較
      - 条件：同じデータを使う
    ## 空の見出し
    """)
    precondition(custom.sections.map(\.headings) == [["選択肢の比較", "品質"], ["次の実験"]])
    precondition(custom.sections[0].groups[0].lines.map(\.text) == ["案：A", "長所：低コスト", "制約：承認が必要"])
    precondition(custom.sections[1].groups[0].lines.map(\.depth) == [0, 1])
    precondition(!custom.hasOmissions)
    var fitted = custom
    precondition(fitted.reduceToFit() && fitted.sections.count == 1 && fitted.hasOmissions)
    precondition(fitted.fullSummary == custom.fullSummary && !fitted.reduceToFit())
    let repeated = MeetingSummaryPosterContent(title: "", date: "", summary: "## 同名\n- 一件目\n## 同名\n- 二件目")
    precondition(Set(repeated.sections.map(\.id)).count == 2)
    let hierarchy = """
    ## 決定事項
    - 公開を延期する
      - 理由：障害の原因は未確認
      - 条件：復旧を確認してから日程を再検討
    - 検証を続ける
    ## アクションアイテム
    - ログを確認する
      - 条件：個人情報は除く
    ## 未決事項
    - 原因
      - 理由：まだ調査中
    """
    let grouped = MarkdownSummaryExtractor.extract(from: hierarchy)
    let posterHierarchy = MeetingSummaryPosterContent(title: "", date: "", summary: hierarchy)
    precondition(posterHierarchy.sections[0].groups[0].lines.map(\.depth) == [0, 1, 1])
    precondition(posterHierarchy.sections[0].groups[0].lines.map(\.text) == ["公開を延期する", "理由：障害の原因は未確認", "条件：復旧を確認してから日程を再検討"])
    var narrowed = posterHierarchy
    precondition(narrowed.reduceToFit())
    precondition(narrowed.sections[0].groups.count == 1)
    precondition(narrowed.sections[0].groups[0].lines == posterHierarchy.sections[0].groups[0].lines)
    precondition(narrowed.fullSummary == hierarchy && narrowed.hasOmissions)
    let many = (1...12).map { "## 話題\($0)\n- 親\n  - 条件：明示されたものだけ\n- 別件\n- 第三項目\n- 第四項目" }.joined(separator: "\n")
    let capped = MeetingSummaryPosterContent(title: "", date: "", summary: many)
    precondition(capped.sections.count == 8 && capped.sections.allSatisfy { $0.groups.count == 3 })
    precondition(capped.hasOmissions && capped.fullSummary == many)
    precondition(grouped.decisions == ["公開を延期する ／ 理由：障害の原因は未確認 ／ 条件：復旧を確認してから日程を再検討", "検証を続ける"])
    precondition(grouped.actions.count == 1 && grouped.actions[0].title == "ログを確認する" && grouped.actions[0].detail == "条件：個人情報は除く")
    precondition(grouped.openQuestions == ["原因 ／ 理由：まだ調査中"])
    let parentless = MarkdownSummaryExtractor.extract(from: "## 決定事項\n  - 理由：原文にある項目\n- 同列の別件")
    precondition(parentless.decisions == ["理由：原文にある項目", "同列の別件"])
    let labelled = MarkdownSummaryExtractor.extract(from: "- **決定事項**:\n  - 延期する\n    - 理由：未確認\n  - 検証する")
    precondition(labelled.decisions == ["延期する ／ 理由：未確認", "検証する"])
    let boldDecision = MarkdownSummaryExtractor.extract(from: "## 決定事項\n- **初回の設定を録音後へ移す**\n  - 理由：設定項目が多い\n- **5人で検証する**\n## アクションアイテム\n- **ログを調べる**")
    precondition(boldDecision.decisions == ["**初回の設定を録音後へ移す** ／ 理由：設定項目が多い", "**5人で検証する**"])
    precondition(boldDecision.actions.count == 1 && boldDecision.actions[0].title == "**ログを調べる**")
    let boldParent = MarkdownSummaryExtractor.extract(from: "## 決定事項\n- **公開を延期する**：\n  - 理由：検証がまだ終わっていない\n- 検証を続ける")
    precondition(boldParent.decisions == ["**公開を延期する**： ／ 理由：検証がまだ終わっていない", "検証を続ける"])
    let blocks = MarkdownBlockParser.sourcedBlocks(for: hierarchy)
    precondition(blocks.contains { if case .bullet(level: 1, marker: .dot, text: "理由：障害の原因は未確認") = $0.block { return true }; return false })
    let child = blocks.first { if case .bullet(_, _, text: "理由：障害の原因は未確認") = $0.block { return true }; return false }!
    precondition(hierarchy.components(separatedBy: "\n")[child.lines.lowerBound] == "  - 理由：障害の原因は未確認")
    print("Meeting summary poster checks passed: source-only excerpts, uncertainty, actions, edits, Unicode limits and full text")
  }
}
