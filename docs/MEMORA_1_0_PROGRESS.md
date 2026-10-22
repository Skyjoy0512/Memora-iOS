# Memora 1.0 品質改善

開始日: 2026-10-22。現在の作業ブランチ: `main`。

進捗: Phase 1〜3のローカル検証済み実装をコミット済み。
Phase 4の安全なコード改善・ホスト計測とJournal回帰を実施。
端末性能の実測を含むPhase 4の全項目、およびPhase 5〜7はまだ完了していない。
実機・実アカウント・GitHub CIの実行は、以下のローカル成功結果とは別扱い。

## Phase 1: 選択統合と品質基盤

GitHubから取得した開始時点のHEAD:

- main: `f41fd399e8bcc7d655b08526010935f7a2f7a046`
- feat/askai-integrated-scenarios: `599ff5e05ff22b7b3395b6ae61f3e2a20f7d1568`
- 共通祖先以降: main側41コミット、対象側11コミット、対象固有18ファイル。

ブランチの一括mergeは行わず、現行mainへ必要な差分だけを前方移植する。
履歴上は対象ブランチをmerge済みにはしない。現行のナビゲーション、
モノトーン、Liquid Glass、Journalのフラットな表示は維持する。

### 対象差分の判断

| 差分 | 判断 |
| --- | --- |
| AskAIIntegrationScenarioChecks、ArtifactOperationsChecks、2つのrunner | 採用。実Office生成・再読込、SQLite保存失敗、人物別許可、出典失効、workspace変更、メール下書き、選択tool制限を再検証 |
| AIPluginExecutionPolicyの選択構築 | 採用。単独コンパイルされる既存policyにAIPlugin依存を持たせず、`+Selection` extensionへ分離 |
| PersonFixtureModelと総合runnerへの登録 | 採用。既存の独立ホストチェックを維持 |
| ProjectSourceFilesの保存先差替え | 修正採用。`MEMORA_HOST_CHECKS`コンパイル時だけ許可し、通常アプリの保存先を環境変数で変更しない |
| ProjectMetadataTransport、WebResearchClientのURLSession設定注入 | 採用。ホスト制限、HTTPS、redirect拒否、cookie/credential/cache無効化、時間・容量制限は維持 |
| ArtifactExportFileとDocumentDetailViewの共有処理 | 修正採用。共有用コピーを作り、削除は一時ディレクトリ直下の通常ファイルだけに限定。原本・ディレクトリ・symlinkを残す検証を追加 |
| compile-ios-app.sh、typecheck-ios-app.sh | 不採用。この登録済みBitrigプロジェクトでは完全なビルドを実行できる。worktreeのproducts pathに依存する代替手順を増やさない |
| 過去のSCENARIO_PHASE2/VALIDATION、backlog追記 | 過去の成功結果を今回の証拠として移植しない。今回の結果をこの文書に記録 |

### 検証の境界

Hostのモデル状態、承認入力、OSサービス、HTTP応答はfixture。
本番domain extension、LocalStore/SQLite、ProjectSourceFiles、Office生成・抽出、
registry/policy、provenanceを通す。実アカウント、OAuth、APIキー、有料APIは使用しない。
既存のCloudSessionChecksは本番CloudAgentSessionと両API形式/JSON/SSEも通す。
この検証は録音ハードウェア・実LLM・実承認UI・Officeの最終描画の証明ではない。

Project.jsonにXcodeテストターゲットはない。`bitrig test -list -json`は
その理由でテストを列挙できなかった。ホストチェック、UI E2E、Bitrigの
Debug/Releaseビルドを別の結果として報告する。

変更前のDebugビルド成功: `2026-10-22T10-03-35-ebf11798.log`、既存警告11件。
選択統合後のDebugビルド成功: `2026-10-22T10-06-03-ff0d7368.log`、既存警告11件。
新規のシナリオ・成果物操作runnerは両方成功。

既存総合チェックの再実行で、現行16スキルに対する旧15件の期待値と、
SwiftUI部分型検査のMemoraSpacing依存漏れを検出して修正。
E2EではLibrary起動・歯車のみの設定ボタン・サイドメニューに合わせ、
古いJournal起動前提と曖昧なテキストlocatorを修正する。
総合検証の最終結果は以下のとおり。

### 品質基盤の再実行

- `run-quality-checks.sh`: next-generation / design-refresh / background-summary /
  composer-layout / optimization の5スイートがすべて終了0。
  ログは `/Volumes/WorkspaceSSD/Development/Temp/memora-phase1-quality-verified/`。
- 実行入口の回帰4テスト成功。失敗後の独立スイート継続、非0コードの保存、
  リポジトリ内・既存・symlink出力先の拒否、相対一時保存先の絶対化を検証。
- Releaseプレビュー成功: `2026-10-22T10-08-36-542fe9ec.log`、既存警告11件。
- 最新Debugプレビュー成功: `2026-10-22T10-14-39-bb7e1097.log`、既存警告11件。
- E2E初回17件は16成功/1失敗。同名プロジェクトlocator修正後の対象1件は成功。
  サイドバーのライト/ダークロゴ、作成morph、添付とdraftの3件は成功。
- 拡大E2E28件は26成功/2失敗、skip・中断0。
  失敗は週カレンダーと編集DatePickerを英語日付で探す旧locator。
  現行の日本語ラベルへ修正。週カレンダーの再実行1件は成功。
  日付選択後も開くシステムpickerを明示的に閉じてから保存するよう修正し、
  日時編集の再実行1件も成功。
  `.e2e/regression/phase1-final/report.json`に失敗を含む元結果を保持。
- 既存Debug操作検証画面を通すE2Eを2件追加。候補の編集・選択→実承認→
  本番dispatcher→SQLite再読込一致と再実行拒否、承認拒否と停止時の非保存が成功。
  `phase1-repaired-controls/report.json`は日時編集を含む3件成功/失敗0/skip0。
  先行の失敗結果は`phase1-repair/`に残し、最終成功と区別する。
- `.github/workflows/quality.yml`を追加。GitHub上での実行は未確認。
  完全なBitrigアプリビルドとUI E2Eはローカルの別検証であり、CIに含めたとは報告しない。

Supervisor/OpenCode Goは既存workflowで限定2ファイルを委任したが、
元のmotionゲートが削除済みProminentTabBarを参照して失敗し、候補の
相対一時保存先とsymlinkログ処理にもreview指摘があった。修正試行中に停止し、
候補は未適用で保存した。上限超過や失敗ゲートの迂回は行っていない。
元のゲートを現行仕様へ修正したうえで、集約入口を別途実装し、上記テストを通した。
委任ログ: `/Volumes/WorkspaceSSD/Development/Agents/MemoraSupervisor/run-0yb0y6eu/`。

画面記録: `docs/qa/memora-1.0/phase1/`。before/afterは同じ端末の観測。
保存した画像を目視した範囲だけを視覚確認済みとする。
Library / Journal / Ask AI / サイドメニュー / Toolsのafter画像を目視した。
Phase 1の選択統合・ローカル品質基盤は完了。実機録音・実サービス・GitHub上の
CI実行は未検証のままであり、全機能の公開判定を済ませた意味ではない。

## Phase 2: Ask AIの統合と実行時の再検証

### 実装

- `addTasksTool`を本番dispatcherから呼ぶdomain extensionへ分離し、重複実装せず
  ホスト検証できるようにした。候補の編集UIやデザインは変更していない。
- 承認前後で選択policyの同一性、スキルの現時点の利用可否、人物scope、
  ワークスペース、復元/保護/中止状態、会議の存在・所属・権限・内容を再確認する。
  policyを削除して無制限に戻す変更も、古い承認では実行しない。
- タスク更新でも復元中を明示的に拒否する。
- 調査のSQLite保存・出典のプロジェクト追加を`+WebResearchStorage`へ分離。
  ファイルI/Oの前後でworkspace、reportの版、source一覧、保存先、処理中状態を確認。
  出典とreportは同じSQLite transactionで保存し、失敗時は新規ファイルだけを除去する。
- 取得抜粋は`.partial`、生成したローカル調査メモは`.complete`と記録する。
  未完了の調査を完了扱いせず、URL/取得日時/抜粋種別を保持する。
- スキルの自動選択は既存の純粋な`MemoraSkill.automaticSelection`、MCP候補は
  `SemanticToolDiscovery.select`を再利用。名前・キーワード方式のまま、追加LLMや
  料金の増加はない。将来の意味的選択はこの選択境界から差し替えられる。

### 検証

- `TaskProposalExecutionChecks`成功。本番read_record相当のdomain処理で保存済み会議の
  要約・決定・文字起こしを取得→AgentConversationLoop→タスク候補→本番approval waiter→
  利用者による候補編集/選択→実SQLite保存/再読込→本番list_tasksでの反映を検証。
  未確定の担当・期限はnil。拒否/中止、18種の承認中変更を端末内/クラウド両方で検証。
- 調査シナリオを拡張し、本番ResearchLoop→抜粋/reportの保存→project追加→再読込→
  DOCX/PPTX実生成/抽出→レポート再編集を確認。出典URL・取得日時・partial範囲・
  未完了状態・資料のproject/provenanceを再読込でも確認。
- 実ファイルactorをテスト側だけで一時停止し、I/O中にworkspace/report/保存先等を
  変更する9ケースを決定的に検証。SQLite ABORT時も2種類の保存documentがrollbackし、
  新規ファイルが残らない。テストの停止処理はアプリには含めない。
- UI E2E: 承認候補の編集/選択とSQLite再読込、拒否/停止、タスク編集/完了/再起動の3件成功。
  `.e2e/regression/phase2-task-approval/report.json`。
- UI E2E: スキルの保存/復元/再編集/指定、未保存編集保護、Tools検索、@候補の4件成功。
  `.e2e/regression/phase2-skills/report.json`。選択7件の失敗/skip/中断は0。
- Debugプレビュー成功: `2026-10-22T16-42-47-da46d626.log`、既存警告11件。
- Releaseプレビュー成功: `2026-10-22T16-53-08-6fcae4be.log`、既存警告11件。
- 途中の集約検証は、コンパイル中のfixture変更と、共用fixtureへのResearch型依存漏れで
  next-generationが失敗した。成功扱いせず元ログを保持し、専用コンパイルflagで依存を分離。
  すべてのSwift/fixture変更を止めた最終集約検証は5系統すべて終了0。
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase2-quality-complete/summary.json`。
  最終結果の要約を`docs/qa/memora-1.0/phase2/validation-summary.json`にも保存した。

モデルによる抽出/要約応答、registry組立、承認入力、HTTP/OSサービスはfixture。
本番CloudAgentSessionのHTTP/SSEは既存の別ホスト検証で確認する。録音ハードウェアから
実LLMまでの接続や実アカウントを通した一連動作、Officeアプリの最終描画は未検証。
構造化UIの比較表/グラフ/カレンダー参照は既存hostのschema・参照権限・型検査を維持。
これを全カードの実機視覚確認とは扱わず、Phase 7の未検証対象に残す。

画面記録: `docs/qa/memora-1.0/phase2/`。本番承認コンポーネントを使うDebug診断の
候補編集後/保存後の2枚を目視確認。表示の再設計はしていない。

### 現時点の公開前の残課題

- P0: 実機での録音継続/中断復旧/音声取り込み/STT再試行、全主要動線、実際の
  VoiceOver/IMEを含む公開前回帰。実認証が必要なGmail/Calendar/Notion/MCPは
  認証なしのfixture検証と区別し、許可を得た試験環境で別途確認する。CIの実行も未確認。
- P1: Phase 4〜6の実測付き性能改善、source UX、外部連携復旧。
- P2: Phase 7の最終視覚確認と、安全に分離できる思考ロゴ案、将来の意味的skill選択。

Phase 2終了時点ではPhase 4の最適化は未着手。この段階のホストbenchmarkは
既存コードの回帰確認であり、今回の新しい性能改善率とは扱わない。
その後の新規実測はPhase 4の節に記録する。端末入力遅延/FPS/メモリ/電池は未測定。

## Phase 3: Journalの追加・編集・保存復旧

### 実装

- 前後のイベントから中間時刻を提案し、末尾は30分後（今日なら現在時刻以降）にする。
  空の過去/未来日は9時。現在時刻の線はイベントに数えず、日付境界とDSTを守る。
  提案は通常のDatePickerで変更できる。イベントへ切り替えても1時間ずらさない。
- 削除はSQLiteの記録/ごみ箱のtransactionが成功したときだけ画面を閉じる。
  復元中・別workspace・保存保護中は単一/一括削除を拒否し、失敗時は記録を保持する。
  写真ファイルの書き込み失敗も、写真なしの保存成功として扱わない。
- 実UIのSQLite失敗試験で、フォーム側とルート側の保存エラー表示が競合し、
  入力フォームが閉じる不具合を検出。同期操作のローカルエラー表示を明示する共通policyを
  追加し、Journalの追加/編集/削除へ適用。非0の保存結果を隠したり、他の非同期エラーを
  一括抑制したりしない。内部基盤は`2ac7650`としてUI変更と分けてコミット。
- 入力済みのタイトル・本文にも明示的なアクセシビリティ名を付けた。
- 外部予定の編集は既存のフルアクセス、書き込み可能calendar、本人所有、非取消が条件。
  編集直前にcalendar IDを指定した±1秒の検索で、event ID/start/endを再照合する。
  別の繰り返し回、削除済み、権限変更、calendar不在なら編集しない。
- 標準EventKitUIの編集画面を同じsheet内で表示し、新しいsheetを重ねない。
  保存/繰り返し選択/エラーは標準UIに委ね、終了後にJournalを再取得する。
  読み取り専用の予定は説明と「カレンダーで開く」を維持する。
  native-app-design / protected-resourcesの指針に沿い、操作と権限を明示した。
  [Appleのsheet指針](https://developer.apple.com/design/human-interface-guidelines/sheets)も参照。
- Project.jsonは既存のcalendar利用目的に「編集」を明記した1行だけ。
  TCC/OAuth scope、capability、deployment target、bundle IDは追加・変更していない。
  フラットな週カレンダー、イベントアイコン、細線、既存Glass/アニメーションは維持。

### 検証

- JournalInsertionTimeChecks成功。中間、同時刻/逆転、選択日、現在線、末尾、
  overflow、DST/日付境界を検証。
- PersonJournalChecks成功。本番追加/日時編集/削除/復元とSQLite再読込、
  最初/最後の書き込みをABORTするrollback、写真失敗、workspace/復元/保護を検証。
- CalendarEventEditPolicyChecks成功。権限・書込可否・所有者・取消と繰り返し回の照合。
  PersistenceFailurePresentationChecks成功。既定のグローバル表示、ローカル/入れ子/throw後の復旧。
- 全ホスト5系統成功: `/Volumes/WorkspaceSSD/Development/Temp/memora-phase3-quality-complete/`。
- Debugプレビュー成功: `2026-10-22T17-57-34-f2a58b95.log`、既存警告11件。
  設定変更後の`bitrig build`とpreviewも実行済み。
- 通常サイズUI E2E3件成功: `phase3-journal-final/report.json`。
  9:00/9:30の間は9:15、eventへの切替、保存/再起動、本文/タイトル/日付編集、
  削除確認の取消/確定と再起動後の非表示を検証。
- 最大アクセシビリティ文字サイズのUI E2E1件成功:
  `phase3-journal-accessibility-xxxl-visible/report.json`。44pt以上の追加ボタン、
  初期時刻/開始時刻、入力欄へのスクロール、選択日と再起動後の復元を確認。
  テスト専用Simulatorは実行後に`large`へ復帰。
- SQLite失敗の実UI E2E1件成功: `phase3-journal-failure-final/report.json`。
  追加/編集の実ABORT後のタイトル・本文保持→解除/再保存→再起動復元、
  ごみ箱側書込ABORT後の詳細保持→解除/再削除→再起動後の非表示を検証。
  独自UUIDを持つUI作成記録から特定できた
  CoreSimulatorのDBだけに一時triggerを作り、finallyでそのtriggerだけを除去する。
  BitrigのプレビューDB・実端末・実アカウントには触れない。
- 今回の選択UIケースは通常3+最大文字1+失敗復旧1の5件。各最終runは失敗/skip/中断0、
  model token/downloadは0。選択していない他ケースは成功に数えない。
  最終結果の要約を`docs/qa/memora-1.0/phase3/validation-summary.json`に保存。
- 初期のE2E失敗はログを保持。通常サイズでは背後の検索結果との重複と、
  popover外をタップする取消動作へ修正。最大文字サイズではAX可視性だけでなく、
  navigation/composerに隠れない座標までスクロールしてから操作する。
  保存失敗時のフォーム消失は実アプリの不具合として上記policyで修正した。

画面: `docs/qa/memora-1.0/phase3/`。通常/最大文字サイズの時刻と復元、
保存失敗で閉じたBeforeと入力が残るAfterを保存・目視確認した。
EventKitUIでの実予定の保存・削除、実アカウント/権限変更、VoiceOverの実音声操作は
未検証。ビルド・純粋policy・JournalのE2Eを、その証明とはしない。

## Phase 4: 内部性能改善（実施中）

### 長期記憶検索

検索のたびに作っていたFTS5を、現在許可された候補の完全一致snapshotで再利用する。
IDだけでなく本文・種別・更新日・出典・人物/workspace・順序を比較し、
候補が変わったら古い索引を捨ててから構築する。失敗時の古い索引へのfallbackはない。
最大2索引、source UTF-8 2MiB/索引、合計16MiBの推定保持コスト、
次回検索時に判定する60秒の非活動期限を導入した。
容量超過でも検索機能は切らず、一時索引として検索後に破棄する。
モデルの記憶・履歴・record/privacy・workspace/person変更時も失効する。
履歴の更新だけならepisode索引のみを破棄し、変わらないsemantic索引を維持する。
同じqueryの重複トークン化も削減。追加LLM・通信・SQLite永続schema変更はない。

実測は[詳細手順](MEMORY_RETRIEVAL_PERFORMANCE.md)と
`docs/qa/memora-1.0/phase4/memory-benchmark.json`に保存。
M4 Max / macOS 27.0.1 / Swift 6.4、`-O -swift-version 5`、
各2,000候補（許可1,600）× semantic/episodeの同一fixtureで3往復比較した。
各21 warm sampleのround中央値を比較すると、2検索の中央値は
40.646ms → 1.966ms（95.16%短縮）。全runで検索結果checksum・scope検証一致。
最大RSSのround中央値は12,386,304 → 13,418,496 bytes（約0.98MiB増加）。
初回は43.608 → 42.897msだが3 sampleだけなので改善を確定しない。
モデルの候補作成/provenanceとiOS UI遅延・FPS・実機電池を測定した数字ではない。
初回構築は引き続き同期処理であり、MainActorのcold-pathは残課題。

### 検証

- `MemoryRetrievalChecks`: 本文/更新日/出典/順序変更、削除、人物・workspace、
  2種の交互利用、種別指定失効、期限、保持上限、容量超過、並行検索が成功。
  最終コードをSwift 6モードでもコンパイル・実行して成功（アプリはSwift 5を維持）。
- ホスト5スイート成功: `/Volumes/WorkspaceSSD/Development/Temp/memora-phase4-memory-quality/`。
- 最新Debug preview成功: `2026-10-22T18-36-54-03d62589.log`、既存警告11件。
- UI E2E初回4件: 3成功/1失敗。履歴menu、会話維持、Journal編集/削除/復元は成功。
  追加ボタンの44pt検査は同名の子Text（14.33pt）を拾うlocatorの不具合。
  待機の追加だけでは解消せず、その失敗も保持。専用Simulatorの実AX treeで
  ボタン本体151.33×44ptと子Text101.33×14.33ptを別々に確認し、roleを明示した。
  失敗結果は`phase4-memory/`、`phase4-memory-insertion-repair/`に保持する。
  role修正後の`phase4-memory-insertion-role/report.json`は1成功/失敗・skip・中断0。
  選択したUI4ケースは最終結果ですべて成功、いずれもmodel token/download 0。

### Journal集計とAskAIの画面処理

`HomeView`のタスク所有判定・活動日・日次サマリー構築を通常Journal表示の
branchへ移し、検索入力ごとのbody更新では表示しない集計を実行しなくした。
検索条件・結果・日付・行・カレンダー・レイアウト・アニメーションは変更していない。
既存の`lifeLogDays`/`markedLifeLogDays`/`markedMeetingDays`と変更時だけの代入を維持。
通常表示でのrecap構築・TimelineBuilderの処理そのものは変更していない。
この変更の入力遅延/FPSの差は未計測。測定なしに時間依存の新しいrecapキャッシュを
増やさず、日付/health/calendar/権限の失効漏れによる複雑化を避けた。

現行AskAIは以下の既存処理を再利用する。今回追加した改善として計上しない。

| 対象 | コードで確認した既存の対策 | 今回の検証と未検証 |
| --- | --- | --- |
| 長文Markdown | StreamingMarkdownView / IncrementalMarkdownCache、確定済みblock再利用 | ホストの全prefix同値/確定block再利用の検証は成功。端末FPS/入力遅延は未計測 |
| 大量会話 | SearchViewのLazyVStackとUUID、AIConversationSnapshotの2,000turn/8MiB境界 | 会話保存/復元・scroll policyのホスト検証は成功。2,000turnの端末scroll/RSSは未計測 |
| 添付 | AIAttachmentTextがTask.detachedで解析、8,000文字までを明示 | 添付scope/拒否と保存のホスト検証は成功。大画像の端末peak memory/電池は未計測 |
| プロジェクト検索 | actor ProjectSearchIndexのexact snapshot再利用と差分同期 | 実FTS/出典/削除/権限変更のホスト検証は成功。端末総応答時間は未計測 |
| AgentActivity | 折りたたみ、直近24step/結果20件/出力8件、elapsedはleaf | ホストの状態・停止・予算検証は成功。活動表示の端末CPU/電池は未計測 |
| 構造化UI | NativeAIResponseCacheとincremental component scan、stream中の操作無効 | schema/参照/承認/失効/streamのホスト検証は成功。全cardの実機描画は未検証 |

追加のJournal E2Eは3件すべて成功、失敗/skip/中断0、model token/download 0。
`phase4-journal-search/report.json`: イベント間時刻と再起動、編集/削除と再起動、
検索結果のみの表示・空結果・クリア・keyboard維持・取消後のタイムライン復帰。
検索中と復帰後の画像を`docs/qa/memora-1.0/phase4/`へ保存して目視した。
見た目の変更ではないので、これを新デザインのBefore/After比較とはしない。

最新Debug preview成功: `2026-10-22T22-33-37-1322e0fa.log`、既存警告11件。
ReleaseのiOS Simulatorビルドも成功:
`2026-10-22T22-37-50-0b5b4814.log`、既存警告11件。SDKは27.1。
これは実機での動作確認・Releaseの端末性能計測ではない。
最終ホスト5スイートもすべて終了0:
`/Volumes/WorkspaceSSD/Development/Temp/memora-phase4-quality-complete/`。
この最終runには種別指定失効の新規検証と、Journal検索branchの静的回帰も含む。
GitHubのmain/対象branchを再fetchし、開始時のHEADから変更がないことも確認した。
pushは実施していない。
結果と失敗/再実行の区別は`docs/qa/memora-1.0/phase4/validation-summary.json`に保存。

### 残る性能確認

- P1: 初回FTSのMainActor同期構築とmodel側provenance/候補作成の実UI計測。
- P1: 通常Journalの日付切替・集計/scroll、長い会話・添付・構造化UIの
  iOS Release上の入力遅延、frame pacing、peak memory、電池。推測値は記載しない。
- P2: 上記計測で根拠が得られた場合だけ、日次集計の追加派生index/cacheや
  非同期検索へ進む。既存の画面/アニメーションは維持する。

## Phase 5: ソース体験（実施中）

### メモの保存境界

- 本番のsource lookup/storeとメモ追加/更新を`+ProjectSourceStorage`へ分離。
  UIは従来と同じAPIを使い、SQLite schemaや既存ファイル形式は変えていない。
- TeamBackend未接続のteam workspaceから、個人用source documentへ書き込まない。
- ファイル書込awaitの前後でworkspace generation、復元/保護/中止、projectの
  存在/版を確認。編集ではsource全体（本文参照・所属・privacy・更新日等）も比較する。
  A→B→Aのworkspace切替、遅れた編集による上書きを拒否する。
- 失敗時は今回生成したファイルだけを除去。成功時も他sourceが参照する古い
  ファイルは削除しない。並行した別メモの追加は両方保存できる。
- 生本文512KBに加え、JSON化したbytesが既存readerの2MB上限以内かも検証。
  超えた場合は専用理由で拒否し、読めない本文を解析済みとして保存しない。
- UIが自分で失敗を表示する場合だけ、同期commitの重複したroot alertを抑止できる。
  awaitの間はこのscopeを保持しない。UIへの適用は次の変更単位で行う。

検証:

- 本番store/note/LocalStore/ProjectSourceFiles/ProjectSourceTextReaderのホスト検証成功。
  24通りの待機中race、SQL ABORTによるrollback/reopen/retry、並行追加、共有参照保持、
  workspace拒否、raw/encodedサイズ境界。状態とevidence通知だけがfixtureで、通信なし。
- 追加runnerはnext-generationに登録。ホスト5スイート成功:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase5-source-storage-quality/`。
  その後追加したencodedサイズ検証を含む専用runnerも再実行して成功。
- UI E2Eは3成功/失敗・skip・中断0:
  `phase5-source-storage/report.json`。Chat/Files/Sources、Webリンク保存後の再表示、
  project mentionのscope/失効/外部write拒否を確認。model token/downloadは0。
- 初期の新規ホスト検証はfixtureのprivate path参照と誤ったUPDATE triggerで失敗した。
  pathをfixture自身で保持し、実INSERT OR REPLACEに対応するINSERT triggerへ修正。
  失敗したrunを成功として数えない。
- 最新Debug preview成功: `2026-10-22T23-22-59-b0ff304c.log`、既存警告11件。

解析状態の表示、古い案内、メモ画面の失敗復旧、YouTube/一般取込の非同期境界の
最終確認はまだ完了していない。Phase 5全体の完了とはしない。

## Phase 6〜7

以下は未完了であり成功扱いしない。

- Phase 6: 外部連携のエラー・権限変更のfixture検証。実認証やOAuth scope拡大は実施しない。
- Phase 7: 視覚・アクセシビリティ・IME・Reduce Motionの最終確認、思考ロゴの調査。
