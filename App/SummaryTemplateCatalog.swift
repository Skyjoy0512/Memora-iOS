import Foundation

/// The templates available beyond the built-ins, for the conversations most
/// business people have: meetings, customers, people, projects and learning.
/// Earlier ids are kept, so templates added in older builds stay added.
enum SummaryTemplateCatalog {
  static let market: [SummaryMarketTemplate] = [
    SummaryMarketTemplate(
      id: "market.regular",
      title: "定例会議",
      detail: "前回からの進捗・課題・決定を整理",
      symbol: .person3,
      lead: "定例会議（進捗・課題・決定）",
      category: .meetings,
      sections: ["前回からの進捗", "課題・リスク", "決まったこと"],
      focus: "進捗は担当者ごとに、課題は影響と対応方針を添えて書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.decisionLog",
      title: "意思決定会議",
      detail: "決めたこと・理由・却下した案を残す",
      symbol: .checkmarkSeal,
      lead: "決定ログ（決めたことと理由）",
      category: .meetings,
      sections: ["決定事項", "判断の理由", "検討して見送った案"],
      focus: "決定ごとに、根拠と前提条件、見送った案とその理由を書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.brainstorm",
      title: "ブレスト",
      detail: "出たアイデアを整理し、有望なものを選ぶ",
      symbol: .lightbulb,
      lead: "ブレスト（アイデアと有望な案）",
      category: .meetings,
      sections: ["出たアイデア", "有望な案と理由", "次に検証すること"],
      focus: "アイデアは似たものをまとめ、発案者が分かれば添える。評価が分かれた点も残す。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.standup",
      title: "デイリー",
      detail: "進捗と止まっている点を短く",
      symbol: .clock,
      lead: "デイリー（進捗と止まっている点）",
      category: .meetings,
      sections: ["昨日やったこと", "今日やること", "困っていること"],
      focus: "一人ずつ短く。止まっている点は誰の助けが要るかを書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.executive",
      title: "経営会議",
      detail: "論点・判断・数値を経営目線で",
      symbol: .chartBar,
      lead: "経営会議（論点・判断・数値）",
      category: .meetings,
      sections: ["主要な数値と状況", "論点", "経営判断", "懸念とリスク"],
      focus: "数値は文字起こしの値をそのまま使い、判断には責任者を添える。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.quickNote",
      title: "打ち合わせメモ",
      detail: "要点だけを箇条書きで短く",
      symbol: .squareAndPencil,
      lead: "打ち合わせメモ（要点だけ）",
      category: .meetings,
      sections: ["要点"],
      focus: "10行以内で、結論と次の行動が分かるように書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.sales",
      title: "商談",
      detail: "顧客の課題・予算・決裁・次の一手",
      symbol: .briefcase,
      lead: "商談（顧客の要望と次の一手）",
      category: .customers,
      sections: ["顧客の状況と課題", "要望・ニーズ", "予算・時期・決裁者", "懸念点・反論", "次の一手"],
      focus: "顧客が実際に言ったことと、こちらの提案を分けて書く。BANT（予算・決裁・ニーズ・時期）で分からない項目は未定とする。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.hearing",
      title: "顧客ヒアリング",
      detail: "現状・課題・理想の状態を聞き取る",
      symbol: .ear,
      lead: "顧客ヒアリング（現状と課題）",
      category: .customers,
      sections: ["現状", "課題と原因", "理想の状態", "追加で確認すること"],
      focus: "顧客の言葉をなるべくそのまま残す。こちらの解釈は分けて書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.proposal",
      title: "提案・プレゼン",
      detail: "伝えた内容と相手の反応",
      symbol: .rectangleOnRectangleAngled,
      lead: "提案（伝えた内容と相手の反応）",
      category: .customers,
      sections: ["提案の要点", "相手の反応・質問", "合意できたこと", "宿題"],
      focus: "質問と回答は対にして書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.complaint",
      title: "クレーム対応",
      detail: "事実・要望・対応内容を正確に",
      symbol: .exclamationmarkBubble,
      lead: "クレーム対応（事実と対応）",
      category: .customers,
      sections: ["発生した事実", "相手の要望・発言", "実施した対応", "合意・約束した内容", "未解決事項", "再発防止に向けた検討事項"],
      focus: "発言・観察事実と評価を分ける。相手の感情やハラスメント認定を推測しない。約束した内容と期限は正確に残す。原音声を確認し、人による確認を必要とする。",
      includesActions: true,
      sensitivityClassification: .sensitive
    ),
    SummaryMarketTemplate(
      id: "market.negotiation",
      title: "交渉",
      detail: "条件・譲歩・合意点を整理",
      symbol: .arrowLeftArrowRight,
      lead: "交渉（条件と合意点）",
      category: .customers,
      sections: ["双方の条件", "譲歩したこと", "合意したこと", "持ち越した論点"],
      focus: "金額・数量・期日は文字起こしのまま正確に書く。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.oneOnOne",
      title: "1on1",
      detail: "本人の状態と次の一歩",
      symbol: .person2,
      lead: "1on1（本人の状態と次の一歩）",
      category: .people,
      sections: ["最近の状況", "悩み・相談", "フィードバック", "次の一歩"],
      focus: "本人の言葉を尊重し、評価的な表現を避ける。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.review",
      title: "評価面談",
      detail: "成果・課題・期待を記録",
      symbol: .starBubble,
      lead: "評価面談（成果と期待）",
      category: .people,
      sections: ["成果", "課題", "今後の期待・目標", "本人の意見"],
      focus: "評価の根拠となる具体例を残す。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.interview",
      title: "採用面接",
      detail: "経歴・強み・懸念・評価",
      symbol: .personBadgeKey,
      lead: "採用面接（経歴と評価）",
      category: .people,
      sections: ["経歴・経験", "強み", "懸念点", "志向・動機", "総合所感"],
      focus: "候補者の発言と面接官の評価を分ける。年齢・家族など採否に関係ない個人情報は書かない。",
      includesActions: false
    ),
    SummaryMarketTemplate(
      id: "market.handover",
      title: "業務引き継ぎ",
      detail: "手順・注意点・連絡先を漏れなく",
      symbol: .arrowRightCircle,
      lead: "引き継ぎ（手順と注意点）",
      category: .people,
      sections: ["業務の概要", "手順", "注意点・よくある問題", "関係者と連絡先", "残っている作業"],
      focus: "手順は番号付きの箇条書きにする。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.kickoff",
      title: "キックオフ",
      detail: "目的・範囲・体制・日程をそろえる",
      symbol: .flag,
      lead: "キックオフ（目的・範囲・体制）",
      category: .projects,
      sections: ["目的・ゴール", "範囲（やること・やらないこと）", "体制と役割", "スケジュール", "リスク"],
      focus: "合意した前提と、まだ決まっていない前提を分ける。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.progress",
      title: "進捗報告",
      detail: "予定と実績の差、課題と対策",
      symbol: .chartLineUptrendXyaxis,
      lead: "進捗報告（予定と実績）",
      category: .projects,
      sections: ["全体の状況", "予定との差", "課題と対策", "支援が必要なこと"],
      focus: "遅れは理由と挽回策を添える。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.retro",
      title: "振り返り（KPT）",
      detail: "続けたいこと・課題・次の試み",
      symbol: .arrowTriangle2Circlepath,
      lead: "振り返り（続けたいこと・課題・次の試み）",
      category: .projects,
      sections: ["Keep（続けたいこと）", "Problem（課題）", "Try（次に試すこと）"],
      focus: "Tryは具体的な行動にする。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.requirements",
      title: "要件定義",
      detail: "やりたいこと・条件・決まっていないこと",
      symbol: .listBulletRectangle,
      lead: "要件定義（要件と未決）",
      category: .projects,
      sections: ["背景と目的", "機能要件", "非機能要件・制約", "未決事項"],
      focus: "要件は一文一要件で書き、優先度が述べられていれば添える。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.seminar",
      title: "セミナー・研修",
      detail: "学んだことと活かし方",
      symbol: .graduationcap,
      lead: "セミナー（学びと活用）",
      category: .learning,
      sections: ["主な内容", "重要なポイント", "自分の業務への活かし方"],
      focus: "講師の主張と具体例を分けて書く。",
      includesActions: false
    ),
    SummaryMarketTemplate(
      id: "market.lecture",
      title: "講演・ウェビナー",
      detail: "論点と根拠を要約",
      symbol: .micFill,
      lead: "講演（論点と根拠）",
      category: .learning,
      sections: ["テーマ", "主な論点", "根拠・事例", "質疑応答"],
      focus: "数値や引用は文字起こしの表記のまま残す。",
      includesActions: false
    ),
    SummaryMarketTemplate(
      id: "market.userInterview",
      title: "ユーザーインタビュー",
      detail: "行動・不満・気づきを抽出",
      symbol: .personWave2,
      lead: "ユーザーインタビュー（行動と不満）",
      category: .learning,
      sections: ["回答者の背景", "行動と使い方", "不満・困りごと", "印象的な発言", "示唆"],
      focus: "印象的な発言はかぎ括弧で原文のまま残す。",
      includesActions: false
    ),
    SummaryMarketTemplate(
      id: "market.press",
      title: "取材",
      detail: "記事に使える事実と発言",
      symbol: .newspaper,
      lead: "取材（事実と発言）",
      category: .learning,
      sections: ["取材相手", "主な事実", "引用できる発言", "確認が必要な点"],
      focus: "引用は原文のまま、要約と分けて書く。",
      includesActions: false
    )
  ] + OccupationSummaryTemplates.all

  static func template(id: String) -> SummaryMarketTemplate? {
    market.first { $0.id == id }
  }
}
