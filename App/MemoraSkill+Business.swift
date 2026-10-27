import Foundation

extension MemoraSkill {
  /// Original procedures. Third-party skill text and executable packages are not bundled.
  static var businessSkills: [Self] {
    let specs: [(String, String, String, [String], String)] = [
      ("proposal", "提案書作成", "目的・読者・提案・費用・根拠を整理", ["提案書"], "doc.richtext"),
      ("executive-report", "経営報告書作成", "事実・指標・意思決定とリスクを区別", ["経営報告"], "chart.bar"),
      ("meeting-report", "会議報告書作成", "議題・決定・担当・未決事項を報告", ["会議報告"], "doc.text"),
      ("business-plan", "企画書作成", "狙い・対象・計画・確認事項を構成", ["企画書"], "square.and.pencil"),
      ("powerpoint", "PowerPoint作成", "65型から内容に合う図表・スライドを作成", ["PowerPoint", "PPTX", "スライド", "経営会議", "営業提案", "事業計画", "市場分析", "競合比較"], "rectangle.on.rectangle.angled"),
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
      var procedure = "依頼の目的と読者を確認し、許可された記録を検索する。根拠のID・日時と現在の許可を確認する。人物はperson_idで識別し、本人の発言と会議全体の決定を分ける。構成を整理し、根拠のない数値・宛先・担当・期限を作らない。" +
        (mail ? "宛先不明は空欄にする。依頼の種類と相手に合わせた件名・本文をdraft_emailへ渡し、通常の承認後に下書き保存する。送信したと報告しない。" :
          "テンプレート指定があれば元の書式を優先する。未登録・未対応なら適用済みと報告せず確認する。資料作成ツールで保存し、本文だけでファイル完成と報告しない。生成形式・編集可能範囲・引用・未確認事項を確認する。")
      if id == "powerpoint" {
        procedure += "まず目的・読者・判断事項・許可された材料と未確認事項を整理し、根拠に対応した主張の列を作る。次に比較・推移・内訳・因果・手順の関係を決めて型を選ぶ。1枚1メッセージ。型名をタイトルにしない。create_slidesのlayoutとcontent_jsonを使い、bulletsは空。sourcesに原資料名と参照箇所、notesに留保を残す。数値を捏造して型を埋めない。自動検査で拒否されたら上限2回まで修正し、不足材料は要確認として報告する。外部調査は依頼の範囲だけ。会社指定は元の書式を優先し、マーカー置換のみ対応の制限を伝える。標準PPTXの図表は編集可能な図形で、Officeのチャートデータ編集ではない。論理・日本語・出典は原資料と見直し、機械検査を事実確認済みと呼ばない。型対応: b01表紙、b02全体マップ、b03目次、b04章扉、b05矢羽、b06前提帰結、b07数値表、b08カード2×2、b09軸表、b10裏表紙、b11主張と図、b12効果表、b13状態ヒートマップ、b14ハーベイ評価、b15ドット割合、b16バブル行列、b17順位棒、b18散布図、b19柱と土台、b20対向矢羽、b21根拠グリッド、b22比例円、b23増減合計、b24シナリオ線、b25調査土台、b26課題施策、b27アジェンダ扉、b28スイムレーン、b29表裏、b30一問一答、m01サマリー、m02根拠整理、m03数値対比、m04KPI、m05図と示唆、m06積み上げ、m07ブリッジ、m08厳密ブリッジ、m09小図比較、m10選択肢表、m11シナリオ表、m12リスク表、m13横軸評価、m14ヒートマップ、m15軸2×2、m16プロセス観点、m17入れ子行、m18時系列行列、m19テーマ、m20提言、m21施策、m22状況課題対策、m23課題施策対応、m24原因解決、m25ツリー、m26現状目標、m27計算、m28フロー、m29循環、m30段階矢羽、m31価値連鎖、m32分岐、m33ロードマップ、m34ガント、m35意思決定。"
      }
      return Self(id: id, name: name, summary: summary, instructions: procedure, keywords: keywords,
        declaredToolNames: tools, declaredPermissions: ["記録の許可を個別に確認。保存・外部処理は既存の承認を使用。"],
        version: 1, iconIdentifier: icon, scopes: [.global, .project, .record, .person], cost: .model)
    }
  }
}
