# 要約の約50秒失敗：調査と回帰検証

調査基点: GitHub main `23230af5e0356a1a5f7d8d4e72ed22b5d937d704`。2026-10-25。

## 結論と完了条件

**利用者が経験した約50秒の失敗の原因は未確定。根本解消済みとは判定しない。**
利用者からBYOK DeepSeekで発生したことを確認済み。該当ジョブのモデルID・HTTP状態・OS中断記録はなく、許可のない有料API実行はしていない。
今回の修正は確認できた終了検証・中断復旧の欠陥と診断不足を解消するもの。

小さい応答で本番受信経路を通すオフラインの実時間テストでは、経過50秒そのものによる固定中断はなかった。
一方、大量のDeepSeek推論deltaを送ると、以下のバイト上限による失敗を実際に再現した。
request timeout 300秒、resource timeout 600秒は延長していない。

## DeepSeek経路で再現した具体的な欠陥

`CloudSSEEventDecoder` と `CloudStreamAccumulator` が、本文だけでなくSSEの繰り返しJSONヘッダーと
非表示の `reasoning_content` にも合計2MiBを適用していた。
DeepSeek公式Chat Completions形式で9,000個の小さな推論deltaを送り、その後に正常な本文とstop/[DONE]を送る
2,178,128バイトのfixtureを作成した。修正前の本番コードで、本文の最初の1文字が届く前に
`AIAnswerFailure.executionLimit` となることを実行して確認した。

修正後は同じfixtureがPASS。通信全体は32MiB、単一イベントと保持する本文は各2MiBに分離し、
要約には使わない推論本文・署名は保持しない。agent turnの既存2MiB上限と推論保持は変更しない。
推論deltaを受けたという実際のイベントだけを最大毎秒1回通知し、要約の状態とOSの進捗に反映。
内容・トークン数・私的な推論は画面にもログにも出さない。keep-aliveを推論進捗と偽装しない。
この回帰テストは6msごとの仮想イベント（約54秒で本文）でも実施した。元の2MiB上限に達する時刻は
この配送レートなら約52秒だが、実際の利用者の配送レートや失敗理由を計測した値ではない。

DeepSeekの `insufficient_system_resource` / `aborted` は、HTTP/通信タイムアウトから分離して扱う。
今回確認したDeepSeek公式APIではthinkingが既定で有効。利用者のモデル/設定は未取得で、すべてのBYOKモデルに同じ既定があるとは仮定しない。待機中のkeep-aliveと推論deltaは別物。
根拠: [Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、
[Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode/)、
[Keep-alive](https://api-docs.deepseek.com/quick_start/rate_limit/)。

この実装欠陥は修正済みだが、実際の50秒事象のエラーがこれだったかは診断ログでの照合が残る。

該当呼び出し: `MemoraModel+SummaryGeneration.generateSummary` →
`MeetingSummarizer.summarize/cloud` → `CloudAIService.completeStreaming` →
`CloudTurnStreaming.response` → `CloudTurnStreamReader.response` →
`CloudSSEEventDecoder.consume` / `CloudStreamAccumulator.consume`。
主な境界は `CloudSSEEventDecoder.maximumBytes` と `CloudStreamAccumulator.maximumSummaryWireBytes`。

## 観測できた原因と経路

| 観測事項 | 原因・対策 |
| --- | --- |
| `FoundationModelFailure` がiOS 27の `LanguageModelError.timeout` を未準備扱い | `.onDeviceTimedOut` に分類。未知の生成エラーも `.generationFailed` とし、未準備と区別。該当区間だけ一度分割可能。ただし50秒事象との同一性は未確認 |
| UIKitの猶予終了が復帰直後の前景処理も停止し得る | `SystemSummaryBackgroundScheduler.begin` の猶予コールバックは前景なら処理を失効させない。Continued Processing側のキャンセルは引き続き尊重 |
| `waitForSummary` の540秒制限が前景にも及ぶ | 上限をバックグラウンドの待機に限定。期限やキャンセル時は再試行確認が必要 |
| 開始済みリクエストに永続的な試行マーカーがない | `PendingSummaryJob.attemptStartedAt` と `requiresUserRetry` を推論前にSQLiteへ保存。保存失敗なら推論しない。再起動後の自動再送を禁止 |
| JSONとSSEの終了検証が不一致 | 通常テキストも `CloudSummaryResponse`、JSONのagent turnも `CloudAgentTurnDecoder` で検証。length/max_tokens・拒否・空・未完了toolを完了扱いしない |
| 408/504、502/503が汎用エラーに混在 | provider timeout/unavailableを分離。URLSession timeout・切断・キャンセルとは別に表示 |

追跡済み: `MeetingSummarizer`, `CloudAIService`, `CloudTurnStreaming`, `CloudTurnStreamReader`,
`CloudStreamAccumulator`, `CloudSummaryResponse`, `OnDeviceSummarizer`, `FoundationModelFailure`,
`MemoraModel+SummaryGeneration`, `MemoraModel+BackgroundSummary`, `MemoraModel+BackgroundSummaryTask`,
`SystemSummaryBackgroundScheduler`, `BackgroundActivity`, `ProcessingService`, `SummaryGenerationSheet`, `PendingSummaryJob`。

保存結果の確定では、元々のrun ID、fingerprint、権限、workspace世代、復元・保護状態の照合と
要約・タスク・ジョブ消去の原子的SQLiteコミットを維持。保存失敗時は旧要約・原文・ジョブを保持する。
クラウドの再送は行わず、明示的なlength終了の継続だけ既存の最大4リクエスト（Anthropicは1）を維持。
汎用chat completions/messagesに、保証されないIdempotency-Keyを付けて安全と称することはしない。
サーバー側のジョブID／重複排除が利用できるサービスとの統合は未実装。

## 診断

`SummaryDiagnostics` のTaskLocalでjob IDを通信まで伝播。OSLog subsystem `app.memora`、category `SummaryTimeline`。
開始日時、エンジン・プロバイダー、モデルのSHA256識別子、入力文字数・区間数、HTTP状態、最初／最後の出力、
解析・保存・失敗・中断の実際のイベントと開始からの経過秒を記録。
本文・URL・キー・トークン・任意のエラー説明は記録しない。モデルIDは利用者が任意文字列を登録できるためハッシュ化する。
端末の診断画面は直近12件・先頭256イベントまで（その後もOSLogへ記録）。大量の分割を行うジョブでは終端が画面の上限外になる制限が残る。OSLogの保持期間はOSが管理する。
「原因を確認」またはDebug設定の「計測と自己チェック → 要約のタイムライン」から確認可能。

## 検証結果

| 条件 | 仮想時間の本番受信ループ | 実時間URLSession（URLProtocol、外部通信なし） |
| --- | --- | --- |
| 30秒 | PASS | PASS: 32.000秒、初回0.002秒 |
| 60秒 | PASS | PASS: 64.043秒、初回0.002秒 |
| 120秒 | PASS | PASS: 128.002秒、初回0.002秒 |
| 180秒 | PASS | PASS: 191.998秒、初回0.002秒 |
| 初回出力60秒後、全体120秒 | PASS | PASS: 初回64.037秒、完了128.002秒 |
| 初回出力60秒後、全体180秒 | PASS | PASS: 初回64.036秒、完了191.997秒 |
| 受信途中の長い無通信区間 | PASS | 上記180秒例で約192秒間または約128秒間の待機後に完了 |
| 終端なしEOF／不完全tool／拒否／空／上限／HTTP異常 | PASS | 既存 `CloudSummaryTransportChecks` 拡充。自動再送なし |
| OS期限・置換・原文編集・権限変更・workspace変更・SQLite ABORT | PASS | `BackgroundSummaryExecutionChecks`: OS/モデルはfixture、保存は本物のSQLite |

実時間の設定値と観測値は別に記録した。Dispatchの実際の配送は遅延する場合がある。
仮想時計はHTTPやOSの期限を仮想化していない。実時間テストも実プロバイダー・iPhoneでの成功を証明しない。

再実行:

```sh
bash tools/checks/run-summary-reliability-checks.sh
bash tools/checks/run-deepseek-summary-checks.sh
bash tools/checks/run-background-summary-job-checks.sh
bash tools/checks/run-cloud-session-checks.sh
MEMORA_REALTIME_SUMMARY_CHECKS=1 bash tools/checks/run-cloud-session-checks.sh
```

## 残る検証

実機のFoundation Models・BGContinuedProcessingTask配信／expiration、実際のアプリ終了・再起動、
Anthropic/OpenAI/OpenRouter/登録BYOKの初回トークン・通信間隔・課金状態は未検証。
次の実際の失敗でタイムラインを採取し、`httpResponse 504`、`.onDeviceTimedOut`、
URLSession -1001、切断 -1005、backgroundExpiration、contextChanged、saveFailedを分けて原因を確定する必要がある。
この証拠と実経路での再検証が揃うまではP0の50秒問題と総合プロジェクトを完了扱いしない。
