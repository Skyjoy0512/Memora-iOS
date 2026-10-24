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
    precondition(content.overview == "予算は10万円ではなく12万円。承認された場合だけ来週実施する。")
    precondition(content.decisions == ["本番切替はしない", "検証環境で比較する"])
    precondition(content.actions == ["予算案を確認 ／ 承認が前提 ／ 担当：佐藤 ／ 期限：来週", "結果を共有 ／ 否決時は延期"])
    precondition(content.questions == ["承認日は未確定"])
    precondition(content.fullSummary == markdown)
    let edited = MeetingSummaryPosterContent(title: "検証用会議", date: "2026/10/24", summary: "本文を修正しました。")
    precondition(edited != content && edited.decisions.isEmpty && edited.actions.isEmpty && edited.questions.isEmpty)
    precondition(edited.overview == "本文を修正しました。")
    let empty = MeetingSummaryPosterContent(title: "", date: "", summary: "")
    precondition(empty.overview.isEmpty && empty.actions.isEmpty)
    let long = String(repeating: "家族👨‍👩‍👧‍👦", count: 300)
    let bounded = MeetingSummaryPosterContent(title: long, date: "", summary: "## 会議の概要\n\(long)\n## 決定事項\n- \(long)")
    precondition(bounded.title.count == 64 && bounded.overview.count == 160 && bounded.decisions[0].count == 72)
    precondition(bounded.fullSummary.contains(long) && bounded.overview.hasSuffix("…"))
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
    precondition(legacy.overview == "条件付きの見積確認。まだ承認はされていない。")
    precondition(legacy.decisions == ["検証環境で比較する"])
    precondition(legacy.actions == ["見積を比較する"])
    precondition(legacy.questions == ["本番への反映日", "承認者"])
    let labels = MeetingSummaryPosterContent(title: "旧形式", date: "", summary: "**日時**: 2026/10/24\n**用件**: 承認前の条件付き検討。")
    precondition(labels.overview == "承認前の条件付き検討。")
    let unknownLabels = "**日程**: 2026/10/24\n**議題**: 条件付きで比較するが、本番切替はまだ承認されていない。"
    let literal = MeetingSummaryPosterContent(title: "旧形式", date: "", summary: unknownLabels)
    precondition(literal.overview == MarkdownBlockParser.plainText(unknownLabels))
    precondition(literal.decisions.isEmpty && literal.actions.isEmpty && literal.fullSummary == unknownLabels)
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
