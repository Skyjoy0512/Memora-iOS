# クラウド要約のバックグラウンド継続 — 2026-10-31 更新

## 開始できない退行の修正

`e6f8bd7` は、iOSの継続枠が届くまで `SummaryExecutionGate` で生成を待たせていた。
利用者から「要約実行できない」と報告があり、この待機は撤去した。前面で開始できる要約を
継続枠の配信に依存させた設計が問題だった。以前のfixture検査は「待つこと」を正解としており、
OSが枠を配信しない場合の前面利用性を保証していなかった。

## 現在の実行契約

1. 原文・生成条件・試行開始マーカーを永続化してから、通常の `ProcessingService` で生成を開始する。
   OSの申請結果や枠の配信を待たない。送信直前の原文・権限・workspace・モデル設定の再確認は維持する。
2. 前面の利用者操作には継続処理を `.fail` で申請する。資源不足で即時配信できない場合も前面の生成を妨げない。
   起動時のwildcard登録、依頼ごとの固有ID、iOS 26/27の申請API分岐は維持する。
3. 枠が届いたら**既に動いている同じ処理**のUIKit猶予を返却し、OSの継続枠に引き継ぐ。
   OSのコールバックは推論を開始・再送しない。実際の進捗イベントを反映する。
4. 申請の受付だけでは背景での実行時間を得たことにしない。枠が届かず背景のUIKit猶予が切れた場合は停止し、
   原文・旧要約・条件を保存して明示的な再試行待ちとする。期限が切れた処理へ遅れて届いた枠は失敗で返却する。
5. 期限切れ・利用者中止・古い通知はジョブIDと実行トークンで隔離する。開始済み依頼を自動再送しない。
   要約・タスク・ジョブ削除のSQLiteトランザクション成功後にだけ、OSへ成功を通知する。

診断の `backgroundRequested` / `backgroundAccepted` / `backgroundGranted` / `backgroundFallback` /
`backgroundRejected` は、申請受付と実枠の取得を区別する。`backgroundWaiting` は過去の診断との互換用に残るが、
現在の処理は記録しない。原文・回答・キー・接続URLをログへ追加していない。

## 検証と境界

- `run-background-summary-job-checks.sh`: 本番キュー・生成domain・ProcessingService・実SQLiteの保存/再読込/ABORT、
  取消・権限変更・二重実行防止に加え、OS境界が枠を全く配信しない場合/申請を拒否する場合の前面開始・結果保存を検査。
- `run-summary-scheduler-checks.py`: 本番スケジューラーを、OSだけ決定的なfixtureに置き換えて検査。
  即時申請、枠受取とUIKit猶予の引継ぎ、未配信時の猶予切れ、遅れた配信の拒否、並行ジョブの隔離を検査。
- `run-cloud-session-checks.sh`: 本番URLSession/SSE/JSON/終了条件/取消/送信失敗をfail-closedなURLProtocolで検査。
  有料APIへは送信しない。
- iOSプレビューと、今回追加した動画要約の操作検査は [SUMMARY_START_VIDEO_2026_10.md](SUMMARY_START_VIDEO_2026_10.md) に記録する。

これらは実OSによる枠の配信や、実プロバイダーの背景完了を証明するテストではない。
実機のBYOKで他アプリ移動・ロック・低電力・OS中止・切断を確認する必要がある。
Memora Intelligenceのサーバー未接続状態は実装によって解消しない。

Project.json、entitlement、Keychain保護、ファイル保護は変更していない。
無音再生などで背景時間を延長する仕組みも追加していない。

## 一次資料

- Apple: [長時間処理の実行と完了](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- Apple: [即時実行できない場合に申請を失敗させるfail戦略](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/submissionstrategy/fail)
- Apple: [ハンドラー登録](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:))
