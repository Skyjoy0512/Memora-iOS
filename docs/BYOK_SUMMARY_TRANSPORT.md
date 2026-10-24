# BYOK要約の通信中断・出力終端の検証

2026-10-25。バックグラウンド要約のOS実行枠は既存の実装を維持し、今回の変更はクラウド受信経路に限定する。実端末の障害ログや実APIは使っていないため、利用者が経験した失敗の原因を特定したとは扱わない。

## 確認した問題と修正

| 対象 | 変更前 | 変更後 |
|---|---|---|
| OpenAI互換の切断 | HTTP本文がEOFになると、正常な終端がなくても受信済み文章を返せた | Ask AIと同じバイト上限付きSSE受信・終端検証を再利用。切断は `connectionLost`。途中の文章を完成として返さない |
| 長さ上限 | 4回目も `length` で終わると途中までの要約を返せた | 既存の最大4リクエストを維持し、未完なら `executionLimit`。切断・拒否・HTTPエラーを自動再送しない |
| Anthropic | 要約は非ストリーミングで待機し、`max_tokens` を成功扱いできた | 同じSSE経路へ接続し、`message_stop` と終了理由を照合。従来の1リクエスト・16,000出力トークン上限を維持し、追加の自動継続はしない |
| 継続入力 | 既出の累積全文を次のassistantメッセージにも繰り返していた | 各部分だけを順に渡す。部分間の空白・改行は保持し、最後に全体の端だけを整える |

- `CloudSummaryResponse` は通常終了と長さ上限を区別し、拒否、終端理由なし、空の文章、不正な構造、tool呼出を受け付けない。非ストリーミングJSONを返す互換サーバーも、その1回の応答を検証する。切替のための追加リクエストは行わない。
- 共有受信処理のデフォルトは従来どおりエージェント用。長さ制限で終わったtool呼出は引き続き拒否する。要約専用モードもtoolを拒否し、実行経路は持たない。
- キャンセルは受信中・応答確定後・次の継続前で確認する。短い応答やJSON応答でも既存の進捗コールバックを通し、許可／workspace変更による停止を次の送信前に反映する。
- 既存の背景失敗処理が `connectionLost` を受け取り、原文・旧要約・保存済み設定を残して明示再試行待ちにする。実際の保存／取り消し／権限検証は既存のdomainとSQLiteを再利用する。
- UI、サマリー画像、タスク追加、ナビゲーション、Liquid Glass、Project.json、OAuth・entitlement・課金設定は変更しない。実APIキー、実アカウント、外部送信、有料APIは検証に使わない。

## 検証

- `tools/checks/run-cloud-session-checks.sh`：本番 `CloudAIService.completeStreaming` → URLSession → 共通SSE/JSON受信 → 要約検証を通る通信検査を追加。Keychain／HTTP応答は明示的なfixtureで、全URLを遮断する `URLProtocol` を使う。OpenAI互換／Anthropicの正常応答、終端欠落、tool混入、空応答、拒否、HTTP 401/403/402/429/500、タイムアウト、切断、キャンセル、継続上限、継続時の改行と入力重複を検査する。
- `tools/checks/run-background-summary-job-checks.sh`：本番キュー・生成domain・ProcessingService、実SQLiteの一括保存／再オープン／ABORT、切断時の再試行待ち、キャンセル・世代・プライバシー変更の既存検査。OSとモデルはfixture。この検査と上記通信検査は別の境界を検証し、実OS＋実クラウドの一気通貫テストとは扱わない。
- `tools/checks/run-next-generation-checks.sh`：共有受信の既存エージェント・権限・データ保存回帰を含めて実行する。
- 最終の通信ホスト検査、背景ジョブ検査、総合 `run-next-generation-checks.sh` は終了0。総合には共有受信のデフォルトのエージェント検証、権限／workspace／個人情報の失効、SQLite失敗／復旧、Officeファイル、プロジェクトソース、音声取り込み、Gmail／Notion／MCPのfixture検査が含まれる。実サービス接続の証明ではない。
- `bitrig preview -platform iOS`：Debug Simulatorビルド成功、プレビュー更新。ログ `2026-10-25T08-01-15-aed987ab.log`。既存の非推奨API等の警告11件。今回はRelease／実機ビルドは未実行。
- UI E2E：`tests/background-summary.e2e.ts` と `tests/summary-adaptive.e2e.ts` の2件成功、失敗／中断／不安定／スキップ0。再開待ち→確認→取消→再起動保持、内容準拠画像と全文、タスク追加・実SQLite保存・再起動・編集欄の復元を確認。予約状態は明示した架空fixtureで、生成処理は開始していない。103件検出のうち未選択101件は今回未実行。
- E2E記録：`.e2e/regression/byok-summary-transport-20261025/report.json` と同フォルダ内のtrace／スクリーンショット。134.54秒は検査所要時間で、AI処理時間ではない。利用者のプレビューDBや実アカウントは使わない。
- 新規ホスト検査の初回コンパイルでは検査コードの結果比較に不備があり修正した。修正前の実行を成功とは扱わず、修正後の通信検査と総合検査がともに成功したことを上記の最終結果とする。

環境：Apple Silicon、macOS 27.0.1、Swift 6.4、iOS Simulator SDK 27.1、専用iPhone 18 Pro Max Simulator。UIのレイアウト／文言は今回変えていないため、新しいBefore／After比較は作成していない。

## 残る確認

P0：実機・実BYOKで、画面オフ／他アプリ移動／OSの継続枠拒否・中止／長時間通信／ファイル保護を確認する。Simulatorとfixtureだけではバックグラウンド完了を保証できない。プロバイダー側の生成停止・課金取消も保証しない。

P1：実機の熱・電池・メモリ・入力遅延の測定。今回は前後の性能数値を計測しておらず、テスト所要時間を性能改善率には換算しない。非ストリーミングの汎用 `complete` と実モデルの要約品質は今回の変更対象外。

OS実行枠の仕様と以前の検証境界は [BACKGROUND_SUMMARY_CONTINUATION.md](BACKGROUND_SUMMARY_CONTINUATION.md) を参照。
