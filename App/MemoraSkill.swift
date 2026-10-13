import Foundation

struct MemoraSkill: Identifiable, Sendable {
  var id: String
  var name: String
  var summary: String
  var instructions: String
  var keywords: [String]

  // Only the shipped catalog can supply procedures. This is not a code loader.
  var skillMarkdown: String {
    "---\nname: \(id)\ndescription: \(summary)\n---\n\n\(instructions)"
  }

  static var bundled: [MemoraSkill] {
    [
      .init(id: "journal-review", name: "ジャーナル分析", summary: "記録に基づく日々の振り返り", instructions: "振り返る期間を特定し、review_periodで実際の記録を確認する。実施したことと予定を分ける。件数は検索上位から推測しない。健康や位置情報を勝手に追加しない。", keywords: ["ジャーナル", "振り返", "journal", "review"]),
      .init(id: "project-organize", name: "プロジェクト整理", summary: "既存プロジェクトと記録の整理", instructions: "list_projectsで現在の所属先を確認する。記録の根拠に基づいて整理を提案する。移動・作成は通常の承認付きツールを使う。同名のプロジェクトを無条件に増やさない。", keywords: ["プロジェクト", "整理", "project", "organize"]),
      .init(id: "travel-plan", name: "旅行計画", summary: "利用可能な資料に基づく旅行計画", instructions: "目的地・日程・制約を利用者の依頼と許可された資料から確認する。Web検索は実際に取得できた情報のみ根拠にする。予約・支払い・外部送信は行わない。不明な料金・営業時間は未確認と示す。", keywords: ["旅行", "旅程", "travel", "trip"])
    ]
  }

  static func context(for request: String, disabled: [String], budget: Int) -> String {
    let selected = bundled.filter { !disabled.contains($0.id) && $0.keywords.contains { request.localizedCaseInsensitiveContains($0) } }.prefix(2)
    guard !selected.isEmpty, budget > 0 else { return "" }
    let guidance = selected.map { "\($0.name): \($0.instructions)" }.joined(separator: "\n")
    return "\n同梱の補助手順です。既存の権限・承認・ツール制限を変更しません。\n" + String(guidance.prefix(budget))
  }
}
