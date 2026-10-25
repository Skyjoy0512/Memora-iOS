# 検証記録（2026-10-25）

## MCP/保存/診断の追加検証

`ed2969d` / `acef618` の後続検査は全6suite Pass:
`/Volumes/WorkspaceSSD/Development/Agents/Codex/tmp/memora-quality/memora-quality-ns8tghh9/summary.json`
コピー [host-summary-mcp-followup.json](host-summary-mcp-followup.json)。MCP POSTの本番actor/HTTP parser/OAuth actorを新たに含む。DNS/HTTP転送/SDK記号/Keychainはfixtureで、実サービス成功を意味しない。

`6a167fb` の診断保持の最終変更は `run-summary-reliability-checks.sh` を再実行してPass。608イベント後も開始・最終token・保存失敗・終了理由を256件以内に保持し、省略352件を確認。仮想30/60/120/180秒、初回60秒、DeepSeek 9,000推論deltaの回帰もPass。今回、前回の実時計191秒通信試験やUI E2Eを再実行したとはしない。

| 追加検証 | 結果 | 境界 |
| --- | --- | --- |
| `run-mcp-pinned-http-checks.sh` | Pass | Swift 6、本番transport/OAuth、IP束縛、HTTP分割/上限、SSE/JSON/ID、early session、切断/late callback、refresh CAS。転送はfixture |
| `run-mcp-agent-checks.sh` | Pass | 63競合、承認/コスト/権限/registry/SQLite境界。実SDK通信はfixture |
| `run-project-source-storage-checks.sh` | Pass | `/private/var`を含む保存先、24競合、原文/SQLite rollback/reopen |
| `run-project-source-import-checks.sh` | Pass | 32競合、file転送/原本保持/SQLite |
| `run-project-source-web-recovery-checks.sh` とfull suite内Web取得 | Pass | 28競合、GET/TLS trust/hostname不一致、bounded HTTP、原本保持。ネットワーク未実行 |
| `ProjectSourceFilesChecks`（optimizationにも含む） | Pass | 既存親/新規leafの正規化、外向きsymlink/不正パス拒否、選択的削除 |
| Debug `bitrig preview -platform iOS` | Pass、preview更新 | `logs/2026-10-25T19-20-50-b3b5d88a.log` |
| Release `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release` | Pass | `logs/2026-10-25T19-19-21-7ae3bb26.log`、最終生成19:22:30。preview中の待機後に再開 |

Debug/Releaseは引き続き既存11 warning。詳細、初期の保存failureによる中断、テスト準備/compile失敗と再検証、HTTP互換性/実機のNot Runは [G](G_MCP_STORAGE_FOLLOWUP.md)。GitHubは再照会しても既存main `23230af`/run `40149268122` のFailのまま。手動push/dispatchは実施していない。

## 環境とデータ境界

- iOS 26 deployment target、Xcode iOS 27.1 SDK。UI E2Eは専用iPhone 18 Pro Max / iOS 27.0 CoreSimulator、実機ではない。
- ビルドはBitrig。Project.jsonにXcode test targetがないため `bitrig test -scheme Memora -destination 'platform=iOS Simulator'` はexit 78 / **Not Run**。既存Swiftホスト検査と既存E2E基盤で検証した。xcodebuildへ迂回していない。
- ホスト検査は外部scratchの合成データと本物のSQLiteを使用。UI fixtureはUI作成UUIDで専用Simulatorの空DBを特定してから投入。利用者のpreview/実データは対象外。
- `agent.*` を使わない決定的E2Eのみ実行。CLIのmodel欄がDeepSeekでも、モデル呼び出しはしない。実プロバイダー課金、外部ツールの副作用、本番変更なし。

## ホスト全体検査：PASS

主変更の固定ソース実行（全suite exit 0、`1711137`時点のapp変更）：
`/Volumes/WorkspaceSSD/Development/Agents/Codex/tmp/memora-quality/memora-quality-g3mec4x7/summary.json`
結果のコピーは [host-summary.json](host-summary.json)。その後の日付/通貨符号・表示サンプルの修正は `run-summary-reading-checks.sh`（図解suiteを含む）を再実行してPass。モデルコンテナはfixtureだが、表示サンプルと図解recipeは実際のAppコードを読み込むよう拡充した。

| Suite | 結果 | 主な対象 |
| --- | --- | --- |
| next-generation | Pass | 要約/図解、録音・資料取り込み、バックアップ、人物/タスク/ジャーナル権限、Agent/MCP/Gmail/Notion fixture、引用/承認/副作用防止、RAG、yomiyasu |
| design-refresh | Pass | 既存デザイン/動作のホスト回帰検査。画面の実見を代替しない |
| background-summary | Pass | durable attempt、期限・中断・run置換、内容/権限/workspace失効、実SQLite ABORT/原文保持/再試行 |
| summary-reliability | Pass | 仮想30/60/120/180秒、初回60秒、無通信区間、切断、DeepSeek >2MiB、Foundation Modelsエラー型、安全な診断 |
| composer-layout | Pass | 既存composerのレイアウト/操作境界 |
| optimization | Pass | collection/index/SQLite/ShareInbox/権限等の現行コードと合成性能 |

`python3 -B tools/checks/test_quality_runner.py`：4件Pass。
追加個別検査：`run-person-privacy-checks.sh`、`run-ask-ai-scenario-checks.sh`、`run-infographic-checks.sh`、`run-summary-reading-checks.sh`、`run-branch-integration-checks.sh`、検索品質の現行/基点比較：Pass。

## 長時間通信：PASS（実プロバイダーではない）

`MEMORA_REALTIME_SUMMARY_CHECKS=1 bash tools/checks/run-cloud-session-checks.sh` を2回実行、両方Pass。
実際のURLSession受信をURLProtocolで供給し、6ケースを並行実行。設定値と観測時間は別：

| 設定 | 最終再実行の観測時間 |
| --- | --- |
| 30秒 | 31.987秒、初回0.003秒 |
| 60秒 | 63.997秒、初回0.002秒 |
| 120秒 | 127.980秒、初回0.002秒 |
| 120秒/初回60秒 | 127.980秒、初回63.997秒 |
| 180秒 | 191.981秒、初回0.002秒 |
| 180秒/初回60秒 | 191.981秒、初回63.997秒 |

本番HTTP timeoutは変更していない。外部通信・APIキーなし。OSスケジューラや実回線/実プロバイダーの保証ではない。
DeepSeekの大量reasoning fixtureでは、修正前executionLimitを実行して確認し、修正後は本文/stopまで同じ入力が完了。

## ビルド

| 検証 | 結果 | ログ（Buildsディレクトリ内） |
| --- | --- | --- |
| Debug / `bitrig preview -platform iOS` | Pass、preview更新済み | `logs/2026-10-25T18-08-29-e0522219.log` |
| Release / `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release` | Pass | `logs/2026-10-25T18-08-30-cc91b37e.log` |
| GitHub Actions | 最新既存mainはFail、修正commitのremote実行はNot Run | [CI報告](CI.md) |

Debug/Releaseとも既存11 warning（認証session/MapKit/CLGeocoderのdeprecation、App Intents metadata等）。今回warningを抑制していない。ビルドログはBitrigが保持する直近件数に制限あり。

## UI E2E

| 検証 | 結果 | 証拠/制限 |
| --- | --- | --- |
| 変更前summary-reading | Pass / 159.89秒 | `.e2e/regression/quality-before-20261025` |
| 日本語全文置換・12段落paste・絵文字/結合文字・画面遷移・SQLite・再起動・Light/Dark | Pass / 116.67秒（個別） | `quality-native-menu-roles-20261025`。後の2テスト一括でもPass |
| 太字/斜体・箇条書き・表セル、変更行以外の全要約と原文の厳密一致・再起動 | Pass | `quality-editing-final-20261025`、markdown-replacement 2件計187.35秒 |
| 再開待ちジョブの復元・生成前のキャンセル・追加処理を行わず原文/要約/ジョブを保持 | Pass / 61.93秒 | 同上background-summary。OSの実期限ではなく保存状態のUI検証 |
| summary-reading最終再検証（PNG・native全文・Dynamic Type最大・日本語編集・再起動） | Pass / 157.82秒 | `quality-summary-final-20261025`。同実行の図解fixtureはFail、実行全体の成功とはしない |
| 条件を保持した図解の復元・根拠・質問draft（送信なし） | Pass / 92.59秒 | `quality-infographics-final-20261025`。実生成ではなく明示UI fixture |
| 既存サンプルの図解・追加保存失敗/再試行・原本保持・編集/再起動/削除 | Pass / 93.55秒 | 同上。図解のaccessible nameもassertし、抜粋への意図しないfallbackを許容しない |
| Ask AI Light/Darkと設定導線・workspace3タブ・週次カレンダー・Journal/workspace Dark | Pass / 4件、224.68秒 | `quality-surfaces-20261025`。空/合成データのみ。実モデル回答は未実行 |

最終の関連E2Eは合計10個の異なるcaseがPass（複数実行の結果。途中のFailや同じcaseの重複を成功件数へ加算しない）。図解条件/否定・日付/通貨符号の最終追加はホストで再検査し、表示サンプルも本番recipeで検証した。

### 発生した失敗と分類

- 最初の日本語`.fill`は期待値末尾に「だ」が残った。ドライバーの `moveCaretToEnd` は複数行の中央右をtapし、最大120回Backspaceする実装だった。全文選択と同一ではない。厳密assertionを保ち、実際のSelect All/Pasteへ変更。
- 親の「Markdownで編集」がネイティブ選択を奪う画面を確認。カスタムmenuは読み取り側の行/セルへ移し、live UITextViewの親には付けない。
- native menuがbuttonでなくlistitemとして公開されることを失敗時のAX treeで確認。根拠に基づきlocatorを修正。3回同じ操作が失敗した時点で再試行を止め、記録を調査した。
- `quality-editing-final-20261025` は3件Pass/1件Fail。summary-readingのDarkで選択menuを発見できなかった。キーボード遷移中の座標操作を既存stableBoundsの確認で保護し、別実行でPass。失敗結果は消していない。
- `quality-summary-final-20261025` はsummary-reading Pass / 図解fixture Fail。条件を省略しないfixtureに更新し、ラベル自体も支持できる中立語に合わせ、`quality-infographics-final-20261025` でPass。図解の本番表示サンプルを実コードで追加検査すると、旧sampleが拒否される回帰も検出。原文句へ合わせ、表内の空白前置き日付と符号のtokenizeを修正してPass。元の要約は変更していない。
- 初期のホスト全体実行はソース更新中のコンパイルで失敗。次の実行はyomiyasu旧2.3.0固定assertionが失敗。2.4.0の固定SHA検査と新ルールのassertionを追加して更新した。assertion削除/skipではない。最終固定ソース実行は全6suite Pass。

使用E2Eは0.21.2。調査時のnpm最新は0.21.3だった。未確認の新バージョンにも同じドライバー問題があるとは主張せず、外部issueは送信していない。

### Not Run（Skipで代用しない）

実機日本語IMEの未確定変換/候補選択、実VoiceOver読み上げ、実機Reduce Motion、実機の中断/force quit/再起動、BGContinuedProcessingTaskの実配信/expiration、実Foundation Models推論、実プロバイダー別TTFT/間隔/課金、実ストレージ満杯/保護状態、録音CPU/電池、外部サービス/OAuth/署名/Office組版。
これらをfixture成功やコンパイルだけでPassとしない。利用者の約50秒事象は診断照合と実経路の検証が残るため、プロジェクト完了とはしない。

再実行の入口：

```sh
python3 -B tools/checks/test_quality_runner.py
bash tools/checks/run-quality-checks.sh --output-dir /absolute/external/new-directory
MEMORA_REALTIME_SUMMARY_CHECKS=1 bash tools/checks/run-cloud-session-checks.sh
npx e2e run tests/markdown-replacement.e2e.ts tests/summary-reading.e2e.ts tests/background-summary.e2e.ts --workers 1 --retries 0 --no-cache
```
