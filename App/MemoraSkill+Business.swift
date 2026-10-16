import Foundation

extension MemoraSkill {
  /// Original procedures. Third-party skill text and executable packages are not bundled.
  static var businessSkills: [Self] {
    let specs: [(String, String, String, [String], String)] = [
      ("proposal", "提案書作成", "目的・読者・提案・費用・根拠を整理", ["提案書"], "doc.richtext"),
      ("executive-report", "経営報告書作成", "事実・指標・意思決定とリスクを区別", ["経営報告"], "chart.bar"),
      ("meeting-report", "会議報告書作成", "議題・決定・担当・未決事項を報告", ["会議報告"], "doc.text"),
      ("business-plan", "企画書作成", "狙い・対象・計画・確認事項を構成", ["企画書"], "square.and.pencil"),
      ("powerpoint", "PowerPoint作成", "編集できるテキスト中心のスライド", ["PowerPoint", "PPTX", "スライド"], "rectangle.on.rectangle.angled"),
      ("word-document", "Word文書作成", "見出し・段落・表を持つ文書", ["Word", "DOCX"], "doc.richtext"),
      ("company-template", "会社テンプレート適用", "元の会社書式と差し込み範囲を確認", ["会社フォーマット", "会社テンプレート"], "doc.on.doc"),
      ("periodic-report", "週報・月報作成", "期間内の成果と予定を分ける", ["週報", "月報"], "calendar"),
      ("research-report", "調査レポート作成", "取得済みの一次資料と不確実性を提示", ["調査レポート"], "magnifyingglass"),
      ("email-draft", "メール下書き", "宛先を推測せず確認用の下書きを保存", ["メール", "下書き"], "envelope"),
      ("meeting-followup", "会議フォローアップ", "会議の決定と次の確認事項から下書き", ["フォローアップ"], "checklist"),
      ("person-conversation", "人物との会話要約", "人物IDと関連記録から根拠付きの要約", ["人物", "この人"], "person")
    ]
    return specs.map { id, name, summary, keywords, icon in
      let mail = id == "email-draft" || id == "meeting-followup"
      let tools = ["search_records", "read_record", "read_person", "list_tasks"] +
        (mail ? ["draft_email"] : [id == "powerpoint" ? "create_slides" : "create_document"])
      let procedure = "依頼の目的と読者を確認し、許可された記録を検索する。根拠のID・日時と現在の許可を確認する。人物はperson_idで識別し、本人の発言と会議全体の決定を分ける。構成を整理し、根拠のない数値・宛先・担当・期限を作らない。" +
        (mail ? "宛先不明は空欄にする。依頼の種類と相手に合わせた件名・本文をdraft_emailへ渡し、通常の承認後に下書き保存する。送信したと報告しない。" :
          "テンプレート指定があれば元の書式を優先する。未登録・未対応なら適用済みと報告せず確認する。資料作成ツールで保存し、本文だけでファイル完成と報告しない。生成形式・編集可能範囲・引用・未確認事項を確認する。")
      return Self(id: id, name: name, summary: summary, instructions: procedure, keywords: keywords,
        declaredToolNames: tools, declaredPermissions: ["記録の許可を個別に確認。保存・外部処理は既存の承認を使用。"],
        version: 1, iconIdentifier: icon, scopes: [.global, .project, .record, .person], cost: .model)
    }
  }
}
