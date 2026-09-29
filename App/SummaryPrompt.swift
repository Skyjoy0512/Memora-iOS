import Foundation

/// What the cloud engine is told when it writes a summary. Kept apart from the
/// Ask AI prompt, whose "answer briefly" framing cut minutes down to a few lines.
enum SummaryPrompt {
  static let system = """
  あなたは日本語の会議議事録を作成する専門家です。与えられた文字起こしだけを根拠に、正確で具体的な議事録を作ります。

  守ること:
  - 文字起こしに無い事実・数値・日付・担当者を作らない。分からない項目は「未定」と書く。期限も、会議で述べられていなければ必ず「未定」にする。
  - 固有名詞・数値・日付・金額・製品名・識別子は文字起こしの表記をそのまま保つ。
  - 音声認識の誤りと思われる語は、文脈から明らかな場合だけ正しい語に直す。判断できない語は、その語の後に「[要確認]」を付ける。
  - 話者は文字起こしのラベル（例: Speaker 1）で呼ぶ。発言内容から役割が明らかでも、名前を推測して付け替えない。
  - 相槌・言い直し・雑談は省き、議論の中身・結論・その理由を残す。
  - 要点は「誰が何を述べ、どう結論したか」が分かる具体的な文で書く。「〜について話した」だけの文にしない。
  - 指定された形式のMarkdownだけを出力し、前置きや締めの言葉は書かない。
  """

  /// The request for one pass over the whole transcript.
  static func document(for input: MeetingSummaryInput, transcript: String) -> String {
    """
    # 会議情報
    \(input.headerLines.joined(separator: "\n"))

    # 出力形式
    \(format(for: input.template, input: input))

    # 抽出データ
    \(dataContract)

    # 文字起こし
    \(transcript)
    """
  }

  /// The request for one part of a transcript too long for a single pass. The
  /// notes are detailed on purpose: the final pass only sees these.
  static func partNotes(
    for input: MeetingSummaryInput,
    part: Int,
    of total: Int,
    range: String,
    transcript: String
  ) -> String {
    """
    # 会議情報
    \(input.headerLines.joined(separator: "\n"))

    これは長い会議の文字起こしを時間順に分けた \(part)/\(total) 番目の部分（\(range)）です。
    後で全体の議事録にまとめるための作業メモを作ってください。

    # 出力形式
    話題が変わるごとに次の形で書く。
    ## [開始時刻-終了時刻] 話題名
    - 関与者: 話者ラベル
    - 要点: 誰が何を述べたか（数値・日付・固有名詞を正確に。複数行可）
    - 決定事項: 決まったことと、その理由
    - 課題・懸念:
    - アクション: 内容 / 責任者（不明なら未定） / 期限（述べられていなければ未定）
    - 未解決の問い:

    # 文字起こし
    \(transcript)
    """
  }

  /// The final pass over the part notes of a long meeting.
  static func merge(for input: MeetingSummaryInput, notes: String) -> String {
    """
    # 会議情報
    \(input.headerLines.joined(separator: "\n"))

    以下は、長い会議の文字起こしを時間順に分けて作った作業メモです。同じ話題が部分をまたいでいる場合は1つにまとめ、全体の議事録を作ってください。

    # 出力形式
    \(format(for: input.template, input: input))

    # 抽出データ
    \(dataContract)

    # 作業メモ
    \(notes)
    """
  }

  /// The machine-readable block after the document, which fills the lists on
  /// the record and the tasks tab.
  static let dataContract = """
  文書の最後に、次のタグで囲んだJSONを1つだけ付ける。文書本文と矛盾しない内容にする。
  <memora-data>
  {"keyPoints": ["会議全体で重要なポイント（3〜7件）"], "decisions": ["会議全体の決定事項（理由があれば含める）"], "openQuestions": ["結論が出なかった問い"], "actions": [{"title": "短い件名", "detail": "何をするか", "owner": "話者ラベルまたは未定", "due": "会議で述べられた期限（YYYY-MM-DD か 述べられた表現）または未定"}]}
  </memora-data>
  該当が無い項目は空の配列にする。actions は文書内のアクションアイテムをすべて、重複なく含める。
  """

  static func format(for template: SummaryTemplateChoice, input: MeetingSummaryInput) -> String {
    switch template {
    case .builtIn(.detailedOverview):
      detailedOverview(input)
    case .builtIn(.meetingMinutes):
      meetingMinutes(input)
    case .builtIn(.detailedMinutes):
      detailedMinutes
    case .builtIn(.actionPlan):
      actionPlan(input)
    case .market(let market):
      marketFormat(market, input: input)
    }
  }

  private static func detailedOverview(_ input: MeetingSummaryInput) -> String {
    """
    次の構成のMarkdownで書く。話題は時間順に並べ、話題が変わるところで分ける（目安として5〜10分に1つ。短い会議でも1つ以上）。

    # {会議の内容が分かる見出し}
    **日時**: \(input.dateText)
    **参加者**: {話者ラベルをカンマ区切り}
    **会議の概要**:
    {3〜6文。主な議題、結論、決定事項、今後の予定が分かるように書く}

    ---
    ## トピック1：{話題名}
    ### サマリー
    - **関与者**: {この話題で発言した話者}
    - **要点**:
      - {誰が何を述べたか。必要なら「」で短く引用してよい}
      - {項目が多い場合は **小見出し**: を付けて入れ子の箇条書きにする}
    - **決定事項**:
      - {決まったこと。無ければ「なし」}
    - **課題・懸念**:
      - {出された懸念やリスク。無ければ「なし」}
    - **予定アクション**:
      - {この話題から生まれた次の動き。無ければ「なし」}
    ### アクションアイテム
    | タイトル | 説明 | 責任者 | 期限 | 備考 |
    |:---|:---|:---|:---|:---|
    | {件名} | {何をするか} | {話者ラベルまたは未定} | {述べられた期限または未定} | {前提・関連など} |
    （アクションが無い話題では、表の代わりに「なし」と1行だけ書く）
    ### オープンクエスチョン
    - {この話題で結論が出なかった問い。無ければ「なし」}

    ---
    ## トピック2：{話題名}
    （以下、同じ構成で続ける）
    """
  }

  private static func meetingMinutes(_ input: MeetingSummaryInput) -> String {
    """
    次の構成のMarkdownで書く。

    ## 会議情報
    > 日時: \(input.dateText)
    > 参加者: {話者ラベル}
    ## 議事録
    ### {話題名}
    - **{観点}**: {内容。誰が何を述べ、どう結論したか}
    （話題ごとに ### を分け、時間順に並べる）
    ## 決定事項
    - {決定事項}（理由: {理由。述べられていなければ省く}）
    ## 今後の予定・アクション項目
    - [ ] {内容}（担当: {話者ラベルまたは未定} / 期限: {述べられた期限または未定}）
    ## 未決事項
    - {結論が出なかった問い}
    """
  }

  private static let detailedMinutes = """
  次の構成のMarkdownで書く。

  ## 会議の要旨
  {3〜5文}
  ## 主要な決定事項
  - {決定事項} - 理由: {理由。述べられていなければ「記載なし」}
  ## アクションアイテム
  - @{話者ラベルまたは未定} - {内容} - 期限: {述べられた期限または未定}
  ## 詳細議事録
  ### [{開始 mm:ss}-{終了 mm:ss}] {話題名}
  - {その時間に話された内容を具体的に}
  （話題が変わるごとに ### を分け、時間順に並べる。会議全体を漏れなく扱う）
  ## 未決事項
  - {結論が出なかった問い}
  """

  private static func actionPlan(_ input: MeetingSummaryInput) -> String {
    """
    次の構成のMarkdownで書く。

    # {会議の内容が分かる見出し}
    **日時**: \(input.dateText)
    **概要**: {2〜3文}
    ## アクションアイテム
    | タイトル | 説明 | 責任者 | 期限 | 備考 |
    |:---|:---|:---|:---|:---|
    | {件名} | {何をするか} | {話者ラベルまたは未定} | {述べられた期限または未定} | {関連する決定や前提} |
    ## 決定事項
    - {決定事項}
    ## 未決事項・確認が必要なこと
    - {結論が出なかった問い}
    """
  }

  private static func marketFormat(_ template: SummaryMarketTemplate, input: MeetingSummaryInput) -> String {
    """
    「\(template.lead)」の観点でまとめる。次の構成のMarkdownで書く。

    # {会議の内容が分かる見出し}
    **日時**: \(input.dateText)
    **概要**: {この観点で重要なことを3〜5文}
    ## {この観点に合った見出し}
    - {具体的な内容。誰が何を述べたか}
    （観点に合わせて ## の見出しを2〜4個立てる）
    ## アクションアイテム
    | タイトル | 説明 | 責任者 | 期限 | 備考 |
    |:---|:---|:---|:---|:---|
    | {件名} | {何をするか} | {話者ラベルまたは未定} | {述べられた期限または未定} | {備考} |
    ## 未決事項
    - {結論が出なかった問い}
    """
  }
}
