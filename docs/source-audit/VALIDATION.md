# 現在の検証結果

2026-11-01。対象実装 `85b6954941c184d15a145ed8510c9f5f4b72e1d3` ＋修正 `e17a84350e072e55dc7a3b7e5ea5e759c48df148`、閲覧/grounding/動画保護 `6bf68526368f46eb5e9c5f1ca4c437d8dcb1bde2`。この文書は今回実行した結果だけを扱い、過去CIを成功証拠にしない。

## 環境とビルド

- 開始時のHEAD/二つのmain remoteは基準 `7ba0305e285706108525c10b5d1a2dc3f4b1a913` と一致。開始時未コミット変更なし。mainのまま作業。ユーザーデータ/既存サンプルの削除・設定リセットなし。
- `bitrig preview -platform iOS` 成功。iOS Simulator arm64/x86_64、アプリと既存拡張をビルド。既存のMapKit/AuthSession非推奨等11 warnings。エラー0。
- 初回P0修正後のbuild log: `Builds/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea/logs/2026-11-01T11-50-05-58e0c3c1.log`。後続変更のbuildは末尾の各工程に記録する。
- 実際のビルド環境はログ上iPhoneSimulator27.2.sdk。追加APIはiOS26以前のもの（FoundationModels/SpeechAnalyzerは26.0 availability）に限定。SDK27.1そのものを用いたビルド結果ではない。
- `bitrig test -list -json`: exit78、Project.json形式にtest targetなし。XCTest成功とはしない。既存のSwift実コードホスト検査を実行した。
- シミュレーター: Bitrig iPhone 18 Pro Maxと、後述の小画面切替。途中で一覧が空になったが再接続。新端末は初回起動となり、既存端末のデータを削除せず別の個人ライブラリで確認。
- 実iPhone/iPad、課金cloud provider、所有者Googleアカウント、CloudKit/teamの実接続は未検証。

## 受け入れ12項目

| # | ケース | 今回の実証 | 未確認/制約 |
|---|---|---|---|
| 1 | Web URL→本文/要約→AskAI | シミュレーターで `https://www.iana.org/help/example-domains` を＋から追加。title/本文/日本語要約が自動生成された。資料限定AI画面を操作 | 初回要約に原文にない疑問が混入しschemaを修正。最終回答は下記操作記録 |
| 2 | 入口が異なる同URL | 同じ正規化/addProjectLinkを共用。URL/ファイル指紋の重複、SQLite再読込をホストテスト | 全入口（共有extension、本文カード、会話）のlive同一URL比較は未完 |
| 3 | 21ページ超PDF | production PDFKitで24ページ生成→全抽出→page24のunique語をSQLite FTSで取得し実ページ引用。2M文字を超えた後半page99も検索 | iOSのPDF viewerでページ24をtapするE2Eは未実施 |
| 4 | scan PDFの限界 | production Visionで5ページをOCR、4ページ目の語を取得、白紙5ページ目をunreadableとして区別、coverage partial | 端末の多言語/表/図精度は未測定 |
| 5 | 音声追加の自動転写/要約 | 共通経路の接続と原本コピー/SQLite/retry/context raceを実行。端末内認識を指定する実装をビルド | m4a/mp3/wavの実音声認識成功は未検証。ホストの音声duration/recognizerはfixture |
| 6 | ローカル動画音声の解析 | AVAsset音声track検査→一時M4A→端末転写の実装をビルド。音声なしの明示失敗経路 | 実mp4/mov、DRM、音声なし/長時間videoの端末試験は未実施 |
| 7 | YouTube合法字幕/取得不可 | production OAuth/公式API serviceをmock認証/HTTPで実行。403/empty/revoke/disconnect、時刻付きcaption、別token境界を検査 | Google実認証/所有動画の取得成功は未検証。任意動画の字幕を保証しない |
| 8 | 複数資料AI→原文 | 最大10添付、後半page関連抜粋、複数reference codec、source引用保持をテスト。資料限定AI画面を操作 | 複数mediaを含むlive質問、添付の任意page/timeへ直接飛ぶアンカーは未完 |
| 9 | 中断/再起動/切断/retry/重複 | 実ファイル/SQLite＋suspended read/writeで取消/rollback/再試行/A→B→A/重複。シミュレーターでbuild再起動後に本文/既存要約保持と中断retry表示を確認 | OS強制終了の全時点、実ネットワーク切断、background完走は未実証 |
| 10 | 個人/project/team/機密 | 実権限policy/世代snapshot/取消race/旧履歴のgrant非復元。team未接続を拒否 | 実backend/複数利用者端末は未接続・未検証 |
| 11 | 既存機能 | 会議要約parser/長文merge/録音import codec/日記/task/資料/PPTX/DOCX/backup/AI履歴/連携のproduction-code suite | 実マイク録音・通知・calendar UI・共有拡張の送信先を全て操作したわけではない |
| 12 | 小画面/dark/Dynamic Type/VoiceOver | 小画面の追加/詳細/質問を操作、最大Dynamic Typeの追加画面で写真追加まで到達。control label/44ptをコード確認 | 全415 viewの手操作/読み上げを保証しない |

## ホストの実コード検査

保管先（外部SSD、リポジトリ外）:
`/Volumes/WorkspaceSSD/Development/Agents/Bitrig/library/Users/23515/Builds/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea/source-audit-validation/`

- `SourceIntakeChecks`: 実PDFKit/Vision/SQLite、24page/scan5page/後半2M超/時刻字幕/旧decode/全体順位付け。モデル・networkのfixtureで成功を置き換えたテストではない。macOS hostの実抽出で、iOS認識・LLM出力品質の証拠ではない。
- `YouTubeCaptionChecks`: PKCE/state/scopes、公式URL、403/字幕なし、切断/権限失効。HTTP/認証UIはfixture。
- `ProjectSourceStorageChecks`: 実ファイル/SQLite/reopen、24 suspended-write race、SQL ABORT/retry、共有参照保護。
- `ProjectSourcePreparationChecks`: 60 race、取消、重複、rollback、reader上限。OS extractionはfixture。
- `ProjectSourceWebRecoveryChecks`: 28 race、安全transport/decoder、更新・復旧・失敗rollback。DNS/HTTPはfixture。
- `ProjectSourceImportChecks`: 実コピー/指紋/SQLite、32 context race、保存済み原本保護。OS処理はfixture。
- `AudioImportChecks`: 新source経路のOpen In/Inbox/重複/SQL再試行＋旧Meeting import/restore/codec。音声認識を実行したという意味ではない。
- `AIConversationSnapshotChecks`: 新source citationと複数添付のcodec、旧履歴decode、path拒否。実行grantは非保存。

全体runnerは `python3 tools/checks/run-quality-checks.py --output-dir <external>`。今回、旧UI名の検査、host fixtureのcalendar/Notion依存不足、新添付budget型のcompile依存不足を発見・修正した。古い検査をskipしたのではなく、新しい保存経路と旧機能保護を検査し直した。初回/途中失敗logも保管している。

最終確認は6系統ともexit0（実行ログは上の外部SSDへ保存）。最初に失敗した総合runnerのsummary.jsonは失敗記録のまま残し、修復後の総合suiteを通し直した別logを採用する。

| 系統 | 今回の最終結果 | 実行log |
|---|---|---|
| next-generation | PASS、全工程を一度通してexit0 | next-generation-complete.log |
| design-refresh | PASS | quality-final-20261101/design-refresh.log |
| background-summary | PASS | quality-final-20261101/background-summary.log |
| summary-reliability | PASS | quality-final-20261101/summary-reliability.log |
| composer-layout | PASS | quality-final-20261101/composer-layout.log |
| optimization | PASS | quality-final-20261101/optimization.log |

その後の画面検証で見つかった自動要約完了との競合は、同じ本文/許可のsnapshotを比較する修正を追加。production `hasSameReadableEvidence` が要約更新を許容し、本文差替え/移動/許可変更を拒否する追加 `SourceIntakeChecks` もPASS。端末内資料schemaの件数上限と再生成の軽量化はiOS buildで検査する。上のsuiteはLLMの全出力品質を保証しない。

## シミュレーター操作の記録

1. 既存Library/サンプルを保持したまま、上部＋→資料追加。
2. 形式/template選択なしでIANA URLを入力・追加。Libraryの同sourceがtitle「Example Domains」に更新。
3. 原文に登録/移転不可の説明を確認。追加操作で本文取得や転写開始を押していない。
4. 初回の日本語要約が表示されたが、原文にない疑問文も出た。資料の端末内schemaを分離して修正。
5. 要約再生成中のbuild再起動で、本文・以前の要約が残り「要約が中断されました」＋retryが表示。自動で外部処理を再送しない。
6. 最終buildでretry、資料だけの質問画面を開き、提供済みsuggestion「要約して」を送信。

成功していない操作は未確認のままにし、接続のない機能を成功と扱わない。

7. 要約が更新された時点で並行中のAskAIがcontextChangedになる現象を再現。生成要約だけの更新と、本文/権限の更新を区別する修正と検査を追加した。
8. 修正途中の資料要約で短い記事でもcontextTooLargeが返った。資料の端末内処理は、各区間で作った要点から概要を組み立て、全topicをもう一度狭いwindowへ送る工程を省いた。旧summaryと原文は保持。最終版の新端末で同URLを再取り込みし、自動要約の成功を確認。原文にない疑問文は今回の出力に含まれず、会議の固定見出しもない。

シミュレーターは一時的に再び非activeとなり `listSimulators` が空。その後iPhone 17eとして再接続したが、画像はOS起動中（Appleロゴ）のため、アプリの小画面確認ではない。再接続後の小画面・最大Dynamic Type・AskAI成功/出典tapは下記へ追記。darkの操作検証は未完。VoiceOverは下記の限定操作を確認。OSのdark設定変更要求は受理されたが、アプリ側の表示設定と実画面の確認を完了していないため、dark検証済みとはしない。

9. 最終buildの小画面端末でログインせず個人ライブラリを開始→＋→同じIANA URL追加。本文と自動要約が成功。最終要約は「ドメイン管理」「参考資料」の内容に応じた見出しで、原文にない疑問文は今回の出力にない。これを全入力のLLM品質保証とはしない。
10. 追加画面を最大Dynamic Typeで確認し、スクロール後の「写真を追加」まで到達。文字サイズとOS appearanceは標準large/lightへ戻した。追加画面/資料詳細の画像をCOMPARISON.mdへ保存。

11. 資料限定AskAIの「要約して」が完了し、記事に対応する回答と出典ボタンを表示。出典tapで保存した本文を開けた。ただし同じ資料・位置のボタン重複と、本文が画面外に残る問題を確認。位置の重複排除とdisclosure展開時のscrollを修正。
12. 端末内AI回答で `example.com` が `例.com` に変形、HTTPサービスの条件を単純化した表現も確認。system指示へ固有名詞/URL/否定・条件保持を追加し、会議限定のroleを資料全般へ変更。出典へ戻れることは回答内容の正しさを保証しない。修正後の応答は追加確認。
13. 動画再生は既存AudioSessionCoordinatorへ接続。録音準備・録音中の再生拒否、録音開始時の停止、他playerへの引き渡し、古いseek後の自動再生抑止を実装。ビルド確認であり、動画/録音の実動作試験ではない。

14. 最後のprompt/引用/動画保護変更後も `bitrig preview -platform iOS` PASS（11 warnings）。追加でchat/experience presentation 19検査、BranchIntegrationChecks、CloudSessionChecksを再実行してPASS。動画のOS動作・LLM意味精度をこれらのhost検査だけで確認済みとはしない。

15. 最後の表示修正で、回答下の同じsource/位置の出典は1ボタンになった。VoiceOverをONにし初回OS説明を閉じ、出典をダブルtapで開くと「原文」が展開され実本文が画面内へスクロール（AX offscreenではない）した。画像source-quote-after.png。その後VoiceOverをOFFへ戻した。読み上げ内容/全画面のジェスチャ認証ではない。
16. 最後の指示変更前の回答では固有名詞を保持したが、作業方針の説明が回答末尾に混入した。本文context内の実行指示をsystem側へ分離し、本文は取得範囲という事実のmetadataだけに変更。最終指示での再生成は追加確認。

## 検証の優先順位の変更

2026-11-01の利用者指示により、アクセシビリティの追加検証は後回しとする。以後は機能をまとめて実装し、区切りでビルドと変更範囲に必要な回帰確認を行う。機能追加のたびの全体テストや、通過済み検査の反復は行わない。

最後のsystem/資料本文の分離変更はビルド成功、BranchIntegrationChecks成功。追加の画面再生成、dark設定操作、アクセシビリティ検証は実施していない。実音声/動画、所有者YouTube実認証、チーム実接続などの未確認事項は表のとおり残る。

## 会話添付の保存・解析再利用の追加改善

2026-11-01、HEAD `606ac16a` からの追加。アクセシビリティ作業は再開せず、次のまとまりだけを実装・検査した。

- 会話添付をライブラリへ保存しても要約完了を待たない。資料名/元URLを登録時に保持し、同じ保存範囲のURL重複を抑止。
- コピー後も内容のSHA-256で解析結果を再利用。同時要求を統合し、形式/音声の用語集が異なる解析は分離。空結果/失敗は再試行可能。これは揮発性cacheであり、再起動後の無再解析を保証しない。
- `source-cache-20261101.log`: production cache/hashingで、コピー再利用、変更本文、形式/用語集、再試行、同時実行、cache clear/解析中の変更、symlink拒否をPASS。OS抽出器はfixtureであり、実音声認識を試験していない。
- `conversation-save-20261101.log`: production file copy/SQLiteで、元URL/表示名/既定privacyの初回保存、要約待ちなし、URL重複時に本文を上書きしないこと、保存範囲分離をPASS。既存32競合/rollback検査も同suiteでPASS。実要約器はfixture。
- 過去の6全体suiteは再実行していない。今回の追加変更に対する結果は上記の限定host検査と別記するiOS preview buildに限る。追加のシミュレーター操作・実機試験は実施していない。
- 最終コードの `bitrig preview -platform iOS` は成功（既存と同じ11 warnings）。log: `logs/2026-11-01T12-00-40-842d2eff.log`。最終レビューで追加した重複競合対策を含む。`git diff --check` も通過。

## P0/P1の並行改善（a158414aから）

利用者の並行実装の指示を受け、解析結果の永続化、添付の全文/位置閲覧、資料の再試行/要約履歴を分担して統合した。追加でrootが未開始pendingの復旧と、SQLite削除成功後の派生cache破棄を接続した。

| 限定検査 | 結果 | 境界/log |
|---|---|---|
| SourceExtractionCacheChecks | PASS | production hashing/SQLite/ファイルで別instance再起動、coverage/thumbnail保持、期限/件数/byte容量、破損/欠落、保存不可、選択削除/取消、同時waiterの1回保存。OS抽出器はfixture。`p1-durable-cache-20261101.log` |
| ProjectSourceWebRecoveryChecks | PASS | 既存28競合と、pending起動復旧/live queue保護/SQL失敗rollback/原本保持。DNS/HTTPとmodel stateはfixture。`p1-pending-recovery-20261101.log` |
| ProjectSourceImportChecks | PASS | 既存32競合/コピー/SQLite/URL重複と、削除成功時だけ派生cache破棄を要求するhook。model hookはfixture、cache本体の選択削除は上の検査。`p1-source-deletion-20261101.log` |

全体6suiteは反復していない。追加UIの端末操作、PDF24ページのtap、音声/videoの実再生、アプリの実プロセス再起動によるcache再利用は未検証。hostでの別instance復元と、iOSでの実際の再起動を区別する。アクセシビリティの追加検証も実施していない。

統合後の `bitrig preview -platform iOS` は成功、プレビュー更新済み（既存と同じ11 warnings）。log: `logs/2026-11-01T12-10-32-3bd7f10b.log`。今回のapp変更をまとめてビルドした結果で、上記UIの操作確認を意味しない。`git diff --check` も通過。

## 添付の出典遷移・PDFページ継続（adf81795から）

添付の実送信抜粋と元ファイル/実ページ/実時刻を回答・履歴へ任意項目として保持し、参照ボタンから原本へ戻す。最終contextで全文が残らない抜粋はボタンの対象外。同一ページでも引用番号と原文が異なる場合は別の根拠として保持する。モデルが書いた任意の番号を参照先にはしない。

PDFは処理済みページをSQLiteへ記録して、取消・時間制限後に継続する。readyな部分本文も明示的な継続操作で更新し、原本を再取得しない。2000ページ/8MBの総上限は維持し、時間停止だけを継続可能と表示する。

| 限定検査 | 結果 | 境界/log |
|---|---|---|
| AttachmentCitationChecks | PASS | production prepare/selection/referenceで後半page24と時刻、Unicode/byte予算、各切断点の実送信全文照合、10資料/64引用、無効な復元情報、一時原本の旧API互換。抽出器はfixture。`attachment-evidence-20261101.log` |
| SourceIntakeChecks | PASS | production PDFKit/Vision/SQLiteで実Task取消、別storeで再開、時間制限後のscan PDF続行、処理済みページの再OCR抑止、原本変更/破損/削除session失効。既存24page/FTS/OCR検査も同suite。macOS hostでありiOS実機ではない。`pdf-checkpoints-20261101.log` |
| ProjectSourceImportChecks | PASS | production SQLite/fileに加え明示的な継続の保存失敗/権限/二重開始拒否、原本/既存本文/プライバシー保持。scheduler/OS解析はfixture。`pdf-continuation-20261101.log` |
| AIConversationSnapshotChecks | PASS | production snapshot/履歴codecで引用復元、旧形式の欠落項目、無効なパス/重複番号/上限拒否、grant非復元。`conversation-evidence-20261101.log` |
| SourceExtractionCacheChecks | PASS | 継続可能な結果を完成cacheへ固定しないこと、完成後の永続再利用。既存破損/失効/削除競合も同suite。OS抽出器はfixture。`continuation-cache-20261101.log` |

既存全体6suite、実機・追加画面のタップ、クラウドモデルの最終出力は再検証していない。参照ボタンの追加をLLMの正答保証としない。追加のアクセシビリティ検証も行っていない。最終レビューの引用番号保持修正後は履歴codec検査のみ再実行し、他の通過済み限定suiteは反復しない。

最終コードの `bitrig preview -platform iOS` は成功、既存と同じ11 warnings。log: `logs/2026-11-01T17-10-40-8261e167.log`。プレビュー更新済み、`git diff --check` も通過。ビルド環境は引き続きSDK27.2であり、追加実装は27.1より新しいAPIを使用していない。

## 資料別の任意要約設定（a4b9ccfeから）

資料詳細のその他メニューにだけ任意の設定シートを追加。まとめ方/詳しさ/AIは資料ごとに保存し、通常の自動取り込みには追加操作を要求しない。キャンセルは保存せず、開始時に本文と送信先のsnapshotを確認してmodel所有jobへ渡す。以前の要約と試行対象の本文参照を分離した。

| 限定検査 | 結果 | 境界/log |
|---|---|---|
| SourceSummaryChecks | PASS | production設定解決/受入れ/要約保存/SQLite/本文reader。適応型の既定、明示設定の再利用、削除済みモデル/形式と非対応長さの拒否、厳格なcloudAI許可、古い要約の出典維持、履歴上限、旧データdecode、SQL開始/完了失敗、13種の設定・原文・権限等の変更。model状態/registry/要約器はfixture、実AI出力ではない。`source-summary-options-20261101.log` |
| ProjectSourcePreparationChecks | PASS | 既存の実source orchestration/SQLite/fileと60競合検査。optional項目を追加したsourceの保存/再読込/取消/rollback/原本保持。OS抽出・network payloadはfixture。`source-summary-compatibility-20261101.log` |

`bitrig preview -platform iOS` は成功、既存と同じ11 warnings。log: `logs/2026-11-01T18-18-39-45ca642e.log`。プレビュー更新済み、`git diff --check` も通過。

追加シートの端末操作、実モデルでの業務template出力、実provider送信は未検証。過去に保存された要約へ、存在しない設定履歴や失われた本文参照を推定して付与しない。既存全体6suiteとアクセシビリティ検証は反復していない。

## 混在PDFの画像文字・OCR失敗復旧（8a5094bbから）

文字layerがあるPDFでも画像XObject/入れ子Form内の文字をOCR対象にし、デジタル本文と結合した。画像資源だけを上限付きで検査し、文字のみのページは追加OCRしない。OCR例外は完了として保存せず、読み取れた本文を保持して失敗時だけ再読み取りを出す。

| 限定検査 | 結果 | 境界/log |
|---|---|---|
| SourceIntakeChecks + MixedPDFExtractionChecks + PDFPageTextMergeChecks | PASS | macOSの実PDFKit/Vision/SQLite。24ページの実PDFで23ページは追加OCRなし、24ページ目の入れ子Form画像内文章とdigital本文を保持し、page24のFTS引用へ到達。見出し重複除去、数字/符号/否定等の違い保持、循環資源、checkpoint再利用を確認。OCR例外だけは注入し、再試行は実Visionでpage24のみ復旧。既存24page・5scan・取消/時間制限等も同suiteでPASS。`mixed-pdf-intake-20261101.log` |
| SourceExtractionCacheChecks | PASS | production hash/SQLite/cacheで旧PDF世代の回避、text cache継続、新PDFの別instance再利用、OCR失敗結果のmemory/disk非固定化。抽出器はfixture。`mixed-pdf-cache-20261101.log` |
| ProjectSourceImportChecks | PASS | production source/SQLite/登録処理と既存32競合。OCR失敗ページの保存/再読込、原本/本文を残す明示再試行と二重開始拒否。scheduler/OS抽出/model状態はfixture。`mixed-pdf-retry-20261101.log` |

最初のhostコンパイルでCoreGraphicsのoptional参照の扱いを修正し、失敗した取り込みsuiteだけを再実行した。通過済み2suiteは反復していない。既存全体6suite、追加ボタンの実操作、実モデルの回答、iOS実機、アクセシビリティを今回検証したとはしない。

inline画像、vector文字、XObject/Form以外の注釈/pattern/maskは検出対象外。OCRは表/図の構造や正確な読み順を復元しない。未使用の画像資源で追加OCRになる場合がある。巨大ページの早期上限判定は追加したが、PDFKit内部の文字列生成・実機のメモリ/電力は未計測。

最終コードの `bitrig preview -platform iOS` は成功、プレビュー更新済み（既存と同じ11 warnings）。log: `logs/2026-11-01T18-35-41-b32b5f88.log`。`git diff --check` も通過。ビルド環境は引き続きSDK27.2で、追加したCoreGraphics/PDFKit/Vision APIは27.1より新しいAPIではない。

## 並行P1: PDF分割追加・旧PDF再読み取り・media領域（7b3278f8から）

独立した3系統を並行実装してrootが統合。作業開始時HEADは `7b3278f86a8e12670efe6b36570373f27ba20bf6`、途中で共有ツリーのHEADが `0c20cfb2ff046ae94a41d160a63bcd3982b2b9fa` へ進み、今回の途中実装とsidebar logo変更を含んでいた。そのcommitを保持したまま残りを完成させた。branchはmain、既存データ/設定の消去はしていない。

| 限定検査 | 結果 | 境界/log |
|---|---|---|
| PDFPartitionChecks | PASS | 実205page PDF→100/100/5pageのnative PDF。後半本文/author/URI注釈、原本hash不変、active flock保護/孤児回収、暗号化/form/symlink/事前取消拒否。production file/SQLiteで全part登録/失敗一括rollback、元hash+範囲の重複抑止、元privacy継承と不一致拒否、古いscope拒否。production schedulerでpartの順次準備、作業本体はfixture。`pdf-partitions-20261101.log` |
| ProjectSourceImportChecks | PASS | 既存32競合に加え、旧ready PDFの再読み取り受入れ/1job/SQL失敗rollback、原本/本文/要約/設定/権限保持、元file不在/消えたproject/実行中/team/復元/保護時の拒否。scheduler/OS抽出はfixture。`pdf-reread-20261101.log` |
| SourceMediaExportChecks | PASS | 実AVFoundationの1秒WAV→M4Aとduration保持、疎fileで100MB超の拒否、fixture空き容量の拒否、開始前取消、flock active保持、孤児/lease作成前領域回収。Speech/実機/in-flight取消の時間は試験していない。`bounded-media-export-20261101.log` |
| ProjectSourcePreparationChecks | PASS | 最終レビューで見つけた再読み取り失敗時の本文不可視化を修正後、production SQLite/fileとfixture抽出で例外/空結果/取消時の以前の本文ready維持、要約参照/取得日時/権限維持、成功時のみ本文置換とrevision保存。既存60競合等も同suite。`pdf-reread-preservation-20261101.log` |

最初の統合previewは成功（`logs/2026-11-01T22-17-46-bee1f512.log`）。その後に発見したPDF再読み取りの保護を実装し、それに必要な4件目の限定検査と最終previewだけを追加した。最終 `bitrig preview -platform iOS` は成功、プレビュー更新済み、既存と同じ11 warnings。log: `logs/2026-11-01T22-21-52-a05efde3.log`。host media検査にあったSendable/明示selfの警告は最終iOS buildまでに修正。通過済み3suite・全体6suiteは反復していない。`git diff --check` 通過。

新しい分割追加/再読み取り画面の実操作、実Speech、長時間media、iOS実機のメモリ/電池/取消時間、課金provider、実teamは未検証。アクセシビリティの追加検証もしていない。SDKは引き続き27.2で、追加APIは27.1より新しいAPIを使っていない。

受け入れ境界: 入力500MB等の上限全部を最大実ファイルで計測した試験ではない。PDFKitの単一writeは取消できず、一時候補が上限を超えてから判定される。文書全体のしおり/添付等は保持を保証せず、UIにも説明する。分割temporaryは中断後に回収するが、SQLite登録前のプロセス終了でWorkspaceFilesへ既にコピーした未参照fileの起動時回収は残る。AskAI/共有拡張/Open Inの大容量PDF自動分割は未接続。

## P1: 分割PDFの未登録コピーを起動時回収（a13a6d07から）

開始時main / `a13a6d07`、未コミット変更なし。UI・Marketplaceは変更していない。
上段で残件としていた「新しい分割追加で登録前に終了したコピー」の回収を実装した。
SQLite journalに作成前の名前を記録し、source保存とjournalの所有解除を同じcommitへ統合。
旧ProjectSourceの形式変更やデータ移行は不要。導入前の未追跡fileは一括削除しない。

| 限定検査 | 結果 | 今回確認した範囲 |
|---|---|---|
| PDFPartitionChecks | PASS | 実205page PDFの分割/後半本文/注釈/元hash/重複/権限継承。実SQLiteでsource書込後のjournal更新をtriggerで失敗させ、全体rollbackとcopy回収を確認。別プロセスを`_exit`で後片付けなし終了させ、登録前はcopyと部分stageを回収、登録後は保存済みcopyを保持。生存中flock、追跡外の旧file、異常なdirectory、壊れたjournalは保護 |
| ProjectSourceStorageChecks | PASS | 変更した共通file copyとproduction source保存・SQLite再読込、既存24競合、共有参照保持、SQL失敗・再試行。model state/通知はfixture |
| ProjectSourceImportChecks | PASS | 共通copy・登録の既存32競合、重複・保存後のfile保持、失敗rollback、PDF再読込・OCR失敗再試行・削除時参照保持。OS抽出/Speech/schedulerはfixture |

最初の限定検査で出たhost helperのactor警告を解消し、commit最後のjournal更新失敗を加えて
PDF suiteを再実行した。通過済みの全体suiteは反復していない。
プロセス終了検査の部分stageはfixtureで作成してから実プロセスを終了するもので、
iOSの強制終了・端末ストレージロック・OSによる途中停止を実機で再現した試験ではない。
実機の性能/電池/メモリ、実AI/Speech/チーム、アクセシビリティの追加検証は未実施。
AskAI/共有拡張/Open Inの大容量PDF分割接続は引き続き残る。

今回の最終 `bitrig preview -platform iOS` は成功、プレビュー更新済み。
log: `logs/2026-11-01T23-08-35-0fba3315.log`、従来と同じ警告11件。
`git diff --check` 通過。新しい画面・設定・SDK27.1より新しいAPIは追加していない。

## P0/P1: 大容量PDF fileの入口統一（6eb261c0から）

開始時main / `6eb261c0`、未コミット変更なし。共有queueとAsk AI添付を独立して分担し、
rootが共通native処理・Library/Open In・共有登録と統合した。Marketplace・権限・AI送信先の変更なし。

| 限定検査 | 結果 | 実証と境界 |
|---|---|---|
| PDFPartitionChecks | PASS | headerがPDFで50MB超の実205page PDF（未使用の疎stream付き）をPDFKitで開き、3part化・後半205page本文・part上限拒否を確認。productionの自動取り込みhelperとSQLiteで重複抑止、会話partとLibraryの元hash/range一致、共有受領記録の一括commit/失敗rollbackを確認 |
| 同suiteの共有経路 | PASS | production `ShareInboxQueue` → `MemoraModel+ShareInbox` → native分割 → SQLite。2項目目の保存をtriggerで失敗させキュー維持、先に保存したpartを所属解除後に再試行しても複製・再所属せず、古いsource snapshot復元でpartが全て消えた場合は元queueから再登録し、最終成功でqueue/受領記録を除去。App Group rootとmodel state/AI準備はfixture |
| ShareInboxChecks | PASS | 実50MB超fileのstreaming受付、拡張子なしPDF、偽PDF/変更後header拒否。疎fileで500MB境界・通常合計/共有全体/queue容量を確認。500MB実本文解析や実extensionの起動ではない |
| AttachmentPartitionImportChecks | PASS | productionの添付import methodを抽出してcompile。partition/copy service fixtureで枠の伝達、全part保存、metadata/旧codec、途中copy失敗/取消時の全新規file回収。実PDFKitとの結合・UIではない |
| AttachmentCitationChecks | PASS | production抜粋選択・引用生成・参照codecにpartition metadataを含め、原文/位置/実送信予算/旧data読込・不正metadata拒否。抽出はfixture。既存fixtureのoptional interpolation警告あり |
| ProjectSourceImportChecks | PASS | 既存32 context競合、実file/SQLite、登録・重複・共有参照保持・失敗rollback・PDF再読込等。OS解析/schedulerはfixture |

共通native検査を通した後、共有itemの後続失敗と受領記録の実model経路を追加し、同suiteを再実行した。
通過済みの全体検査は反復していない。iOS buildは別途最終結果を下に記録する。
今回追加した入口の実file picker/共有拡張/Open In操作、実機の500MB/1万page負荷、cloud回答の品質、
実Speech/チーム、アクセシビリティの追加検証は未実施。HTTP取得の50MB上限と会話の10添付枠は維持。

最終統合レビューで、プロジェクト内Ask AIの旧処理が複合添付の先頭fileしか
保存しない点を確認し、全fileの登録・解析・許可確認を通ってから送信するよう修正した。
このプロジェクト送信の変更はコードレビューとiOS buildの対象であり、
複数添付の実UI操作・実AI回答を検証した結果とは扱わない。

最終 `bitrig preview -platform iOS` は成功し、利用者のプレビューを更新した。
log: `logs/2026-11-02T07-12-10-464695c9.log`、既存と同じ警告11件。
途中の共有receipt closureで出た明示self不足のcompile errorは修正済み。
後から追加されたUI指定を同じ最終previewへ含め、全host suiteの反復はしていない。
SDK27.1より新しいAPI・設定変更・破壊的移行は追加していない。
UIの実確認は[比較記録](../ui-minimal-2026-11/README.md)に分離する。

## P0/P1: 添付送信準備の中断・会話・下書き保護（32b165dbから）

開始時main / `32b165db`、未コミット変更なし。UIの見た目、Liquid Glass、
ピル切替、Marketplace、保存データ形式は変更していない。

`MEMORA_CHECK_ROOT=…/Builds/<project> python3 tools/checks/run-composer-request-checks.py` PASS。
productionの`AIComposerRequestContext`・`LocalImportContext`・添付型・リクエスト型と、
`QuickAIComposer`の取消判定・global/projectの送信準備methodをそのままcompileする。
view storage、modelのI/O・解析・AI送信だけfixtureへ置換したhost検査である。

- 通常Ask AIの抽出を待たせ、会話ID・workspace世代・下書き・主IDを維持した複合添付・
  モデル・Marketplace表示・選択画面・navigation path・@指定の9変更で送信なし、入力保持。
- projectのfile copy／本文準備をそれぞれ待たせ、下書き・添付・workspace・画面・モデル・
  scopeだけの変更・取消の7変更（計14）で、後続fileの登録・会話作成・質問送信なし、入力保持、古いエラーなし。
- 送信開始時の遅れたcallbackで新しいTaskを止めないこと、明示停止、古い確認からの
  入力/scope不一致拒否、2添付の正常送信・成功時だけ入力を外すこと、Task/contextの解除。

OSのfile picker・Speech・PDFKit・SQLite・実provider、SwiftUIのonChange/onDisappear
の実発火・停止操作を端末で試した検査ではない。実機・ライブAIと追加アクセシビリティ検証は未実施。
初回の限定検査後、確認待ち/解析中のscope変更と取消後のnil登録結果の扱いをレビューで修正し、
同じ限定suiteだけを再実行した。全host suite・既存のPDF/音声検査は反復していない。

最終 `bitrig preview -platform iOS` は成功、プレビュー更新済み。
log: `logs/2026-11-02T07-23-10-f83e32db.log`、既存の非推奨API等の警告11件、compile errorなし。
`git diff --check`通過。ビルドは動作の実機検証とは分けて扱う。

## P0: プロジェクトAsk AIの質問中URL（7573f885から）

開始時main / `7573f885`、未コミット変更なし。UIのレイアウト、Liquid Glass、
Marketplace、既存データ形式・許可は変更していない。

限定`run-composer-request-checks.py` PASS。前節のproduction送信準備/contextに加え、
実`InlineURLDetector`・`ProjectSourceURL`・`addProjectLink` methodと新しい質問リンクhelperをcompile。
保存・解析・AI dispatch・view stateはfixtureで、HTTPや外部サービスは呼ばない。

- tracking/fragment/host表記が異なる同一URLを1資料として登録し、同じprojectへ保持。
- 添付なしURL、2添付＋URL、既存の許可済みURL、外部送信不許可での停止と端末内への再送を確認。
  重複時に元資料名/URL/権限を上書きしない。新規sourceのprivacyを自動で許可しない。
- Web本文なし・YouTube字幕なしではfixtureの失敗理由を表示し、質問送信・下書き消去なし。
- URL準備を待機し、入力変更・workspace変更・停止の3ケースで、先に保存した1資料を保持し、
  後続URLや質問を実行しない。unsafe/http/認証情報付きURLは検出対象外で取得に進まない。
- 従来25の競合検査も同じsuiteで確認。うち追加2件は、async側のscopeを変更せず
  modelのvisibleProjectIDだけ変えたcopy/本文待機後の拒否で、view値の捕捉を模す。

実際のDNS固定・リダイレクト・HTML/PDF/Speech/公式字幕通信は既存のproduction経路を再利用するが、
今回の限定検査はそれらやSQLite/FTS/実回答品質を実行した証拠ではない。
実シミュレーターでのURL入力からの完走、実機・provider・YouTube所有者権限は未検証。
初回検査後に保存先変更後の失敗理由を別projectから読まないguardと既存/unsafe URLケースを加え、
同じ限定suiteだけを再実行。全host suite・既存のPDF/音声検査は反復していない。

## URLメモと下書きの保護（ae91acd5から）

開始時main / `ae91acd5`、未コミット変更なし。
`run-project-source-storage-checks.sh` PASS。productionのDraftStore、LocalStore、
URL正規化/追加method、note/store methodを使い、実SQLite/file上で以下を確認した。

- draft未保存と有効な空本文を区別。日本語/改行/引用、旧JSON文字列の読込、DB再open。
- 読取失敗、JSON不正、不正UTF-8、0byte blobをunreadableとして扱い、元bytesを保持。
  最初の検査で0byte blobがmissingになるproductionの誤りを検出し、LocalStoreを修正して再実行成功。
- 新規URLと重複URLで、タイトルdraft削除へのSQL failureを注入。
  先行するsource書込/本文draft削除もrollbackし、再試行で両draftが消えることを確認。
  重複では元source全体とIDが等しく、準備jobの追加dispatchがない。
- 前回のnote一括保存と、24の停止中書込競合/実fileのrollback等も同じsuiteで成功。

RecordStoreの外側は同期SQLiteを使うfixtureであり、productionの非同期保存queueの順序や
legacy UserDefaults再移行を端末上で実行した証拠ではない。準備jobはdispatch記録のみで、
HTTP・要約・外部AIは呼ばない。破損した利用者のdraftを作って実アプリに注入していない。

`run-composer-request-checks.py` PASS。同じproduction URL追加methodの既定引数を使う
プロジェクト質問経路、既存25の文脈競合・中断・複合添付・stale承認を確認した。
エディタのdraft commitはcomposer fixtureでは実行せず、上記の実SQLite検査で確認する。
既存のエディタ表示契約1件も成功。全suite・追加アクセシビリティ検査は反復していない。

最終 `bitrig preview -platform iOS` 成功、既存警告11件、利用者のプレビュー更新済み。
log: `logs/2026-11-02T13-52-15-ac050b52.log`。
iPhone18 Pro/ダークのsimulatorで、正常な空draftからメモ画面が編集可能になること、
検証用本文を入力して保存ボタンが有効になること、閉じる→開き直すと本文が復元することを
画像/座標操作で確認した。入力した検証用本文は空へ戻して閉じ、メモ/資料の本登録や
AI送信は行わない。破損/読取失敗のエラー画面、URL保存失敗の端末操作は未検証で、
上記hostでの実SQLite/codec検査と静的な画面接続確認の範囲に限る。実機は未検証。

最終 `bitrig preview -platform iOS` 成功、プレビュー更新済み。
log: `logs/2026-11-02T07-34-05-7eb2e97f.log`、既存警告11件、compile errorなし。
`git diff --check`通過。今回の新経路を実端末で完走したとの扱いはしない。


## 長時間音声・動画の区間処理（fb1dd22bから）

利用者の指定「動作確認はまとめて」に従い、この変更では実音声認識・media fixtureの
実行・シミュレーター操作・全suiteの再実行は行わない。以下のビルド成功を、転写や
引用の実動作成功としては扱わない。

- `bitrig preview -platform iOS`: 成功。既存警告11件、プレビュー更新済み。
  log: `logs/2026-11-02T15-39-36-2e3f46a6.log`。
- `git diff --check`: 成功。
- 静的確認: 音声/動画の共通取り込みから15分区間のtimeRange exportへ接続し、
  区間内時刻を原本時刻へ変換する。leaseは各反復を抜ける時点で解放し、途中失敗は
  空の結果/例外で戻すため、成功した前半だけをsourceへ保存しない。
- 既存の`run-source-media-export-checks.sh`には、最終端数/6時間の区間計画、不正duration、
  実AVFoundationの指定範囲exportとlease回収の項目を追加。今回の変更後は未実行。

まとめて行う確認:

1. m4a/mp3/wav/mp4/movで15分未満・15分境界・15分超・6時間上限を扱えるか。
2. 15分より後ろの発言を検索/AskAIで参照し、引用から原本の正しい時刻へ戻れるか。
3. 無発言区間を挟む資料、音声なしvideo、非対応codec/DRM、後半区間での失敗・取消。
4. 途中停止後に原本が残り、誤った全文要約を作らず、明示的に再試行できるか。
5. 大きな本文でJSON容量を超えると失敗説明が出るか。実機のメモリ/電池/一時容量。
6. 通常の録音/Meetingの文字起こしと要約、既存の時刻引用が変わらないか。

既存データのschema/原本/IDは変更しない。50MB超原本の取り込み、区間単位の永続再開、
境界での音声認識精度は未対応または未検証として残す。


## 音声・動画の区間再開（9063f14dから）

利用者の指定に従い、動作確認はまとめて行う。今回は実音声認識、端末操作、host fixture、
全suiteを実行していない。以下の成功は区間再開・転写・削除raceの実動作成功ではない。

- `bitrig preview -platform iOS`: 成功、プレビュー更新済み、既存警告11件。
  log: `logs/2026-11-02T15-54-59-68abc26b.log`。
- `git diff --check`: 成功。
- 静的確認: security scope内の有界固定コピー→原本hash/config別prefix→未完了区間→
  原本照合→完成本文の順。cache破棄callbackでcheckpoint世代も失効し、古い世代は
  保存しない。localeをqueue前に捕捉し、完了cacheと全区間に同じlocaleを使う。
- 後日の共通host検査`run-source-extraction-cache-checks.sh`へ追加:
  実SQLiteのprefix再読込、無音prefixと全無音完了の違い、原本時刻への復元、
  locale/用語集のkey分離、削除/clear後の古い書込拒否、別指紋のprefix保持、
  不正JSON/時刻、同サイズ/mtime保持の原本変更検出、locale捕捉/切替/完了cache再利用。
  これらの追加検査は未実行であり、合格とは扱わない。

まとめて行う端末確認:

1. 2区間以上の実音声/動画で後半の認識中に停止・プロセス終了→再起動→明示的再試行。
   完了prefixがある場合に前半を再認識せず、引用時刻が原本に合うこと。
2. 第一区間が無音、後半だけ発言、全区間無音、後半の認識失敗・取消・対応資産未導入。
3. 言語/用語集の変更、cache退避/期限切れ/容量上限/保存失敗、原本の差し替え。
4. 解析中の資料削除、workspace切替、privacy変更の後に古い本文を公開しないこと。
5. 実機の一時領域・コピー/再hashの負荷、メモリ・電池、既存Meetingの転写/要約回帰。

元の50MB/6時間上限は維持。区間cacheは派生情報であり、cacheがなければ先頭へ戻る。
保存先範囲/アクセス権をcacheで拡大せず、再起動だけで勝手に認識を実行しない。
