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
    print("Meeting summary poster checks passed: source-only excerpts, uncertainty, actions, edits, Unicode limits and full text")
  }
}
