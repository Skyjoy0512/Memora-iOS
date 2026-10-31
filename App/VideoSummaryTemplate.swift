import Foundation

/// Viewer-facing content must not become meeting decisions or assigned work.
enum VideoSummaryTemplate {
  static let useCase = SummaryUseCase(id: "video-content", title: "動画・配信・ポッドキャスト",
    description: "視聴・聴取した内容を整理", templateIDs: [template.id])

  static let template = SummaryMarketTemplate(
    id: "content.video", title: "動画・配信の要約",
    detail: "YouTube・解説動画・ポッドキャストの要点と具体例を整理",
    symbol: .video, lead: "動画・配信・ポッドキャストの内容要約", category: .learning,
    sections: ["重要なポイント", "内容の流れ", "具体例・データ", "主張・注意点"],
    focus: """
    会議の議事録ではなく、視聴者・聴取者が内容を理解するための要約にする。
    重要なポイントは結論と理由、内容の流れは話題の順にまとめる。手順・比較・具体例・数値は原文にある場合だけ残す。
    発信者の意見・体験談・宣伝と、発信者が示した事実・根拠を区別する。外部検証していない主張を確定した事実として書かない。
    チャンネル登録・購入・視聴者への一般的な勧めをタスクにしない。会議の参加者・決定事項・担当・期限・未決事項の見出しを追加しない。
    JSONのdecisions・actionsは空配列にする。記録の保存日時を公開日や収録日にしない。
    長さが不明または0秒なら、入力の時刻ラベルから章の開始時刻を作らない。日時・時刻・作者・URLは原文にある場合だけ記載する。
    """, includesActions: false)

  static func sectionItems(_ items: [String: [String]]) -> [(title: String, items: [String])] {
    var seen: Set<String> = []
    return template.sections.compactMap { title in
      let unique = (items[title] ?? []).filter { item in
        let key = item.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
          .filter { !$0.isWhitespace }
        return !key.isEmpty && seen.insert(key).inserted
      }
      return unique.isEmpty ? nil : (title, unique)
    }
  }

}
