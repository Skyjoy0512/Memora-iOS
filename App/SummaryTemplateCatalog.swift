import Foundation

/// The templates available beyond the built-ins, for the conversations most
/// business people have: meetings, customers, people, projects and learning.
/// Earlier ids are kept, so templates added in older builds stay added.
enum SummaryTemplateCatalog {
  static let market: [SummaryMarketTemplate] = [
    VideoSummaryTemplate.template,
    SummaryMarketTemplate(
      id: "market.regular",
      title: "定例会議",
      detail: "前回からの進捗・課題・決定を整理",
      symbol: .person3,
      lead: "定例会議（進捗・課題・決定）",
      category: .meetings,
      sections: ["前回からの進捗", "課題・リスク", "決まったこと"],
      focus: "前回から変わったこと、変わっていないこと、会議で確定したことを分ける。進捗・担当・影響・対策は発言された範囲だけで、未報告を未着手とみなさない。",
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
      focus: "決定・提案・保留を分け、明示された決定だけを決定事項にする。根拠・前提・見送った案と理由は述べられたものだけ残す。反対意見を合意としてまとめない。",
      includesActions: true
    ),
    SummaryMarketTemplate(
      id: "market.brainstorm",
      title: "ブレスト",
      detail: "アイデア・評価・検証案を整理",
      symbol: .lightbulb,
      lead: "ブレスト（アイデアと有望な案）",
      category: .meetings,
      sections: ["出たアイデア", "有望な案と理由", "次に検証すること"],
      focus: "似たアイデアをまとめる。会議で評価された案と未評価の案を区別し、AIが勝手に順位や推奨案を作らない。発案者・評価理由・検証案は発言がある場合だけ残す。",
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
      focus: "話者ごとに実績・予定・障害を短く分ける。「昨日」「今日」は発言の表現を保ち、録音日から日付を推定しない。支援者は明示された場合だけ記載する。",
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
      focus: "数値は単位・対象期間・比較基準と一緒に原文どおり残す。実績・予測・目標を分ける。判断、責任者、承認状態は明言された場合だけ記載する。",
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
      focus: "顧客が実際に言ったことと、こちらの提案を分けて書く。BANT（予算・決裁・ニーズ・時期）の未言及は「記載なし」、当事者が未定と述べたものだけ「未定」とする。受注見込みや購買意欲を推測しない。",
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
      focus: "本人の相談・希望と、相手の助言・合意を分ける。感情や能力を推測・診断しない。次の一歩は当事者が決めた内容だけ残す。",
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
      focus: "本人の自己評価と評価者の所見を区別し、述べられた具体例を添える。AIが評点、能力や達成度を判断しない。合意した目標と提案段階の目標を分ける。",
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
      focus: "候補者の経験・発言と面接官が明示した評価を分ける。評価者の発言がない総合所感や採否・適性の判断をAIで作らない。採否に無関係な個人情報は書かない。",
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
      focus: "実績・予定・見込みを分け、予定との差と対象期間を示す。遅延の原因と挽回策は発言された範囲だけ残し、不明な理由を補わない。",
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
      focus: "Keep/Problem/Tryには実際に挙がった内容だけを書く。Tryの提案と合意済みの行動を分け、担当や期限を補完しない。",
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
      sections: ["主な内容", "重要なポイント", "紹介された活用例"],
      focus: "講師の主張・根拠・具体例を分ける。紹介された活用例だけを残し、視聴者の業務や今後の行動を創作しない。",
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
      focus: "発言、報告された行動、聞き手の解釈を区別する。引用は短い逐語引用に限る。示唆は記録で述べられたものだけとし、少数の発言を全利用者の傾向へ一般化しない。",
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
