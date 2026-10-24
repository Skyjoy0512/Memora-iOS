import Foundation

/// Display-only example. No audio, model response or external connection is claimed.
enum SummarizedAudioSample {
  static let id = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
  static let title = "発売準備ミーティング（サンプル）"
  static let summary = """
  ## 会議の概要
  **公開前に録音フローの迷いを減らす。** 初回テストで録音開始までに操作を迷う人がいたため、説明より先に録音できる流れを検証する。公開日はまだ決めない。

  ## 決定事項
  - **初回の設定を録音後へ移す**
    - 理由：初回テストでは、設定項目の多さが録音開始を妨げていた。
    - 条件：マイクの利用目的と録音への同意は、開始前に伝える。
  - **先に5人で検証し、結果を見て公開日を決める**
    - 理由：改善の効果はまだ確認できていない。

  ## 判断の背景
  - 録音ボタンより先に設定が目に入る。
    - 影響：初めて使う人が、録音前に設定を終える必要があると受け取った。
    - そのため：説明を削るのではなく、必要な場面で順に示す。

  ## アクションアイテム
  | タイトル | 詳細 | 担当 | 期限 |
  | --- | --- | --- | --- |
  | 初回録音フローの試作 | 設定を録音後へ移す案を作る | 田中 | 10月28日 |
  | 5人の検証日程を調整 | 同意説明を含む一連の操作を確認する | 佐藤 | 10月29日 |

  ## 未解決事項
  - 公開日は検証結果を見て決める。
  - 録音後に表示する設定の範囲は未定。
  """

  static func make() -> Meeting {
    Meeting(id: id, title: title, createdAt: Date(timeIntervalSince1970: 1_792_800_000),
      duration: 1080, source: .importFile, status: .ready, summary: summary,
      keyPoints: ["同意説明は録音前に残す", "効果はまだ未確認"],
      decisions: ["初回の設定を録音後へ移す", "5人で検証してから公開日を決める"],
      openQuestions: ["公開日", "録音後に表示する設定の範囲"], transcript: [
        TranscriptSegment(id: UUID(uuidString: "77777777-7777-7777-7777-777777777701")!,
          speaker: "田中", speakerIsCertain: true, timestamp: 18,
          text: "えーと、初回テストでは設定項目が多くて、録音前に全部終える必要があると思った人がいました。なので設定は録音後に移して、必要な場面で順に示す案を10月28日までに私が作ります。"),
        TranscriptSegment(id: UUID(uuidString: "77777777-7777-7777-7777-777777777702")!,
          speaker: "佐藤", speakerIsCertain: true, timestamp: 155,
          text: "ただ、マイクの利用目的と録音への同意は開始前に伝えましょう。効果はまだ未確認なので、先に5人で検証してから公開日を決めることで合意です。日程は私が10月29日までに調整します。録音後に表示する設定の範囲は未定です。")
      ], notes: "表示確認用の架空データ。音声ファイルは含まれず、文字起こし・要約の処理は実行していません。")
  }
}
