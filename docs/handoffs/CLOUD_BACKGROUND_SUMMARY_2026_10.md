# クラウド要約のバックグラウンド継続 — 2026-10-31

利用者から、クラウド（BYOK / Memora Intelligence）の要約がバックグラウンドでまだ停止すると報告された。実端末の停止ログや有料APIは今回取得・実行していないため、個別の停止原因を一つに断定しない。既存コードには、継続枠が渡る前に推論を開始し、即時実行を拒否された場合に短いUIKit猶予だけで走る経路が残っていた。

## 修正した実行順序

1. 起動時にInfo.plistの許可リストと同じ `bundleID.summaries.continued.*` のハンドラーを1回登録する。各依頼には引き続き再利用しない固有IDを使い、遅れた通知を元のジョブにだけ対応させる。
2. 利用者が生成を依頼したら、既存の原文・条件・試行マーカーを保存し、継続処理を `.queue` で申請する。iOS 27の非同期申請を別のdetached Taskへ遅らせず、前面の依頼の流れで呼ぶ。iOS 26の同期申請は維持する。
3. 申請の受付と実行枠の取得を区別する。新しい `SummaryExecutionGate` で、実際に `BGContinuedProcessingTask` が渡されるまで同じ生成処理を待たせる。受付通知だけではクラウドへ送信しない。画面には「iOSの継続実行枠を待っています」と表示する。
4. まだ推論を送っていない予約待ちでは、短いUIKit猶予の期限だけで予約と要約を取り消さない。バックグラウンドで実行枠が渡されたら、待っていた同じ生成を1回だけ進める。OSのコールバックから2個目の要約は作らない。
5. 登録/申請が拒否された場合は、前面にいるときだけ従来の前面処理へ進む。待ちの解除と推論開始の間にアプリが背景へ移った場合も再確認する。拒否後の前面処理の猶予が切れたとき、OS中止、入力/権限変更では安全に再試行待ちへ戻す。
6. 要約と抽出タスクをSQLiteへ同時保存できたときだけOSへ成功を返す。待機中の取消、古い実行枠・期限通知、他のジョブ、前面/背景の切替で二重送信や別処理の取消を起こさない。

自動復旧・自動要約は、利用者の新しい操作なしに継続枠を申請しない。開始済みのクラウド依頼を自動再送しない試行マーカー、送信直前の原文/プライバシー/モデル/workspace確認、旧要約保持、保存失敗時のロールバックは維持する。途中のAI文字列を保存して続きを自動生成する実装は追加していない。

## 診断

既存の要約診断に `backgroundRequested` / `backgroundAccepted` / `backgroundWaiting` / `backgroundGranted` / `backgroundFallback` / `backgroundRejected` を追加。
受付後にまだ枠が来ていない場合と、枠を取得してから通信や保存で失敗した場合を分けて調べられる。拒否時はOSの数値コードを記録し、原文・プロンプト・回答・APIキー・接続URLはログへ出さない。進捗は実際の処理イベントを使い、待ち時間から完成率を作らない。

## 検査

- `bash tools/checks/run-background-summary-job-checks.sh`: 通過。既存のcodec、本番キュー/生成/ProcessingService/タスク抽出と実SQLiteの保存・ABORT・再読込・取消検査に加え、枠待ちでは推論ゼロ、背景での枠受取後の保存、待機中の取消/原文訂正/権限失効/workspace変更、前面fallback解除直前の背景移行を検査した。推論とOSはfixture。
- `python3 tools/checks/run-summary-scheduler-checks.py`: 通過。**本番SystemSummaryBackgroundSchedulerの処理本体**をコンパイルし、UIKit/BackgroundTasksの境界だけを決定的なfixtureへ差し替える。wildcardの1回登録、queue、受付と枠の区別、短い猶予切れ後の待機維持、背景での枠受取、取消/遅延通知/置換、並行2件の独立性、登録/申請拒否、前面fallback、OS完了通知の重複防止、自動ジョブの申請禁止を検査した。実OSのスケジューリングを再現した試験ではない。
- `bash tools/checks/run-cloud-session-checks.sh`: 通過。本番クラウド要約からURLSession、SSE/JSON受信、終了条件、取消、HTTP/接続失敗、継続回数上限を検査。両API形式、関連する権限/予算/SQLiteも既存検査が通過。fail-closedなURLProtocolであり、実プロバイダーへ通信・課金していない。
- `git diff --check`: 通過。

## ビルドと端末での確認範囲

`bitrig preview -platform iOS`: success、既存警告11件、新規コンパイルエラーなし。最終ログは `2026-10-31T10-11-06-7b74bfef.log`。iPhone 18 Pro Maxのライブラリが起動し、自己チェック失敗ログは0件。実APIキー・実音声・有料リクエストでの背景完了を試したものではない。

生成済みアプリのInfo.plistで、実bundle IDへ展開された継続処理のwildcardと `processing` モードを確認。Project.json、entitlement、ファイル保護、Keychainの保護設定は変更していない。無音の再生で背景時間を確保する処理は追加していない。

## 残る実機確認

実機のクラウド接続で、他アプリへ移動/画面ロックして要約が完了すること、OSの表示・中止・資源不足・低電力・通信切断を確認する必要がある。今回の検査は実際のクラウド要約が背景で完了したという証拠ではない。

OSが実行枠を拒否・終了したり、利用者がアプリを強制終了した場合まで、アプリだけで処理を無制限に継続できるとはしない。中止された開始済み依頼は原文と設定を残して再試行待ちとし、課金済みの可能性がある通信を勝手に再送しない。

## 参照した一次資料

- Apple: [長時間処理の実行、queue/fail、進捗、完了と中止](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- Apple: [継続処理の開始条件](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)
- Apple: [ハンドラーの登録](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:))
- XcodeのiOS 27.1 SDK `BackgroundTasks.framework/Headers` も照合した。既存のiOS 27用申請APIはavailability分岐を維持する。
