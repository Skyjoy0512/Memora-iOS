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
  awaitの間はこのscopeを保持しない。画面への適用は以下の独立したUI変更で行った。

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

### 解析状態とメモ画面

- 状態表示を`本文解析済み / 一部解析済み / 本文抽出済み · 解析範囲未確認`へ整理。
  抽出状態と外部AIの参照許可を混同させない。YouTubeのタイトルだけなら
  `メタデータのみ`と表示し、音声/字幕未取得の既存説明を維持する。
  canProvideTextやprivacyの判定、保存codecは変更していない。
- Source追加の「右下の＋」を現行の「右上の＋」へ修正。
  App内の右下/下部＋/旧タブ案内の文字列を検索し、他の該当案内は見つからなかった。
- メモ追加/編集の同期commitだけをローカル失敗表示へ接続し、重複root alertで
  フォームが閉じないようにした。追加時の失敗メッセージは画面内へスクロールする。
- 既存の本文draft IDを維持し、同じDraftStore/SQLiteにタイトル用のIDを追加。
  成功時だけ両方をクリアし、失敗後の閉じる/再起動/再編集でも復元する。
  編集保存中の入力/取消/スワイプ閉じを止め、新しい入力を保存結果で消さない。
- 入力済みのTextFieldにも明示的なアクセシビリティ名を付けた。
  Chat/Files/Sources、フラットな行、native sheet/field、Glassは維持している。

検証:

- ホスト5スイート成功:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase5-source-ui-quality/`。
  各形式の未取得/解析中/失敗、旧codec、partial/complete、YouTube metadata、
  private-by-defaultと本文利用判定を含む。新しい画面の構造契約も成功。
- Debug preview成功: `2026-10-22T23-32-21-d5fdb573.log`、既存警告11件。
- UI E2E初回4件は3成功/1失敗:
  `phase5-source-ui/report.json`。project mention、Journal失敗復旧、sourceメモ失敗復旧は成功。
  リンクの空欄をXCTestがplaceholderとして返すことによる期待値の失敗は保持する。
  空文字か正確なplaceholderだけを認める判定へ修正し、重複防止の検査は維持した。
- 再実行+追加Office E2Eは2成功/失敗・skip・中断0:
  `phase5-source-ui-repaired/report.json`。同じURLを2回保存して行は1件。
  Officeは既存Debug診断から本番import/extraction/file/SQLite/添付解析を通し、
  3形式の保存再読込一致とWord本文の再表示、`一部解析済み`の説明、専用データの削除を検証。
  Officeアプリ/QuickLookの最終レイアウトや外部認証を確認した意味ではない。
- 選択したUI5ケースはそれぞれ最終成功。全runのmodel token/downloadは0。
  sourceの新規メモ失敗→タイトル/本文の保持→閉じる→再起動→再保存、
  編集失敗→保持→取消→再起動→再編集→保存→再起動後の本文を確認した。
  共通化したSQLite fixture特定ヘルパーはJournalの実失敗復旧でも再実行して成功。
- Lightの追加失敗、Darkの編集失敗と復元、Office partial説明の4画像を保存・目視した:
  `docs/qa/memora-1.0/phase5/`。新デザインのBefore/After比較や未観測画面の証明とはしない。
- 最終Release Simulatorビルドも成功:
  `2026-10-22T23-44-25-ab00f9d4.log`、SDK 27.1、既存警告11件
  （Swift非推奨10箇所とextensionのmetadata抽出対象なし1件）。実機検証ではない。
- 実装コミットは`31981d4`（保存境界）と`110ef01`（画面・文言・E2E）。
  検証結果は`docs/qa/memora-1.0/phase5/validation-summary.json`にも保存。
  branchはmainのまま、pushは実施していない。性能改善値はこの変更では計測していない。

### 取得・解析結果の非同期境界（2026-10-23）

- YouTube metadata/thumbnailと登録済みローカルsourceの解析を、既存サービスを
  呼ぶ本番のorchestrationとして分離。結果型は共通ファイルに移し、既存の
  `ProjectSourceExtraction.Result`名はtypealiasで維持した。UIや保存schemaは変更しない。
- 共通contextでsource全体、親projectの版、workspace generationを保持。
  await後と保存直前に比較し、privacy/タイトル/所属/種類/削除、A→B→A、復元/保護、
  中止による古い結果の反映を拒否する。失効後は次のthumbnail取得へ進まない。
- メタデータ保存時は既存のmetadataキーを保持。thumbnailだけ失敗した場合は
  保存済みタイトルを保持し、明示的再試行でmetadataを重複取得しない。
  YouTube本文・字幕の取得やAI参照許可を追加したわけではない。
- 失敗/失効時は今回作成した結果ファイルだけを除去。元ファイルは保持する。
  成功時の旧結果ファイルも、別sourceが参照していれば削除しない。
- 解析結果のJSONが既存readerの2MBを超える場合は専用理由で失敗にする。
  読めない結果をreadyとして保存しない。rawファイルの50MB上限とは区別する。

検証:

- 新規runnerの本番orchestration・LocalStore・file actor・readerによる検証成功。
  metadata応答、thumbnail応答、抽出応答、thumbnail書込、本文書込の5境界×
  12状態変更＝60通りで、遅れた結果と新規ファイルを残さないことを確認。
  中止2系統、二重実行の拒否、SQL ABORT後のrollback/reopen/retryも含む。
  model state/evidence通知と通信/抽出/downsampleのpayloadはfixtureであり、
  実YouTube通信・Vision/PDFKit・画像品質を検証した意味ではない。
- ホスト5スイートすべて成功（終了0）:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase5-preparation-quality/`。
  その後、開始保存失敗2系統とmetadata保存失敗後の次段取得拒否を追加し、
  専用runnerを再実行して成功。SQL失敗の検証は合計5ケース。
- 初回の新規fixtureコンパイルはthrow/awaitをpreconditionのautoclosureへ渡して
  失敗した。通常のBoolを受け取る検証helperへ修正し、以後の実行は成功。
  この初回失敗は成功に数えない。
- 最新Debug preview成功: `2026-10-23T07-56-37-9cd56d6d.log`、既存警告11件。
- Release Simulatorビルドも成功: `2026-10-23T07-58-23-eac86cc6.log`、SDK 27.1、
  既存警告11件。実機の動作/性能を確認した意味ではない。
- UI E2Eは2実行/2成功、失敗・skip・中断0:
  `.e2e/regression/phase5-preparation/report.json`、model token/download 0。
  Officeの本番取込/抽出/SQLite再読込と、メモのSQL失敗/下書き/再起動/再保存を再検証。
  検出79件のうち選択した2件だけであり、他77件は実行/成功に数えない。
- OfficeのLight表示と再起動後のメモのDark表示を保存し、目視した。
  `preparation-office-source-partial-coverage.png`と`preparation-note-restored.png`。
  画面を再設計したBefore/After比較ではなく、内部変更後の回帰確認画像。
- 実装コミット`e11d151`。詳細結果はPhase 5の`preparation-validation-summary.json`。
  mainのまま、pushや新しい実認証/外部送信は実施していない。

### 中断状態の復旧と明示的Web取得（2026-10-23）

- 本番のWeb取得も既存`ProjectSourcePreparationContext`へ接続。
  応答後と本文ファイル書込後にsource全体、親projectの版、workspace generation、
  operation所有IDを確認する。privacy/タイトル/metadata/URL/所属/削除やA→B→A後の
  古い結果・失敗理由を現在のsourceへ反映しない。旧処理は新しい処理のbusy表示も消さない。
- WebSourceFetcherの公開HTTPS/DNS/TLS/redirect/MIME/size/time/cookie制限は変更しない。
  書込関数の差し込みは本番orchestrationの保存後境界を確実に検証するためのもので、
  通常は従来のfile actorへ直接保存する。新しい権限や自動取得は追加していない。
- `recoverInterruptedProjectSources`は古いcontextではなく**現在の配列**を使い、
  実行中IDを持たないprocessing項目のstatus/noticeだけを同期保存する。
  タイトル、日時、URL、本文/元ファイル/thumbnail参照、metadata、privacyは保持。
  YouTubeはmetadata-only/unavailable、他形式は失敗・手動再試行可能な状態にする。
- 起動時、処理終了時、Webジョブ失効時、復元完了時に上記の整理を行う。
  実行中のsource、team workspace、復元中、保護されたstoreへは書き込まない。
  SQLiteが失敗した場合はmodelだけ先行させず、ファイルも削除しない。
  これで前節に残したP1の「解析中」残存を修正。自動再開/再取得はしない。

検証:

- 専用ホスト検証成功。本番fetch orchestration/Fetcher/HTML抽出/file actor/LocalStoreを通す。
  HTTP応答待ちと実際の本文ファイル書込完了後の2境界×14状態変更＝28通りで、
  遅れた結果を拒否し新規ファイルを回収。キャンセル/新旧operation所有権、
  SQL ABORT後のrollback/reopen/retry、旧本文と共有ファイル保持も確認。
- 復旧は7形式×5状態の35項目で実行中IDの除外と、status/notice以外の厳密な一致、
  元ファイル/本文/thumbnail保持、再読込、二重実行でSQLを書かないことを確認。
  復旧保存のSQL ABORT時はmodel/SQLite/ファイルを維持し、再試行で成功する。
- 前回の解析60 raceも、中断状態の整理だけを認める期待値へ更新して成功。
  抽出内容やprivacy等を古い結果で置換していないことを引き続き厳密比較する。
- HTTP/DNS payloadとmodel state/evidence通知はfixture。実TLS通信の新規実行、
  実YouTube、写真/OCR、実バックアップ復元中断のSimulator動作を確認した意味ではない。
- 初期のDI既定closureに不要await警告が1件出たため修正。最終Debug previewは成功、
  `2026-10-23T08-12-56-59a59a6c.log`、既存警告11件に戻った。
- 最終ホスト5スイートもすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase5-web-recovery-final-quality/`。
  初期runも5スイート成功だが、警告修正と実ファイル保持検証追加後に全体を再実行した。
- Release Simulatorビルド成功: `2026-10-23T08-15-03-6d8f2f54.log`、SDK 27.1、
  既存警告11件。実機確認・性能計測を行った意味ではない。
- UI E2Eは3実行/3成功、失敗・skip・中断0:
  `.e2e/regression/phase5-web-recovery/report.json`。検出80件のうち77件は対象外で未実行。
  起動時復旧、Office取込/抽出/SQLite再読込、Journalの追加/編集/削除のSQL失敗復旧。
  model token/downloadは0、実アカウントやLLMを使わない専用CoreSimulator。
- 起動時復旧E2Eは、UIで作った唯一のWeb sourceに専用SQLite内でprocessingを設定。
  再起動後の中断理由・手動取得ボタン、status/notice以外の保存値の一致、
  本文参照未生成、再々起動後の一致を確認。実HTTP送受信を端末で計測した検証ではない。
  当該画面を`source-interruption-recovered-without-fetch.png`へ保存し目視した。
  これは復旧後の1画面で、Before/After比較や他画面の視覚確認の代わりとはしない。
- 実装コミット`bb138ea`。結果はPhase 5の`web-recovery-validation-summary.json`。
  mainのまま、pushや外部サービスの新しい認証/権限拡大は実施していない。

### 登録前の取込境界と音声原本の保持（2026-10-23）

- `LocalImportContext`で個人workspace generationと親project全体を保持する。
  ProjectSourceAddSheetはnative写真/ファイルPickerを開く**前**に取得し、
  loadTransferable/copyの前後、登録後にも照合する。team・復元中・store保護・
  project編集/削除・A→B→A・cancel後の古い結果を保存/成功表示しない。
- 既存file actor・SHA重複排除・SQLite schema・解析ルーターを再利用。
  未登録の新規コピーは失効/保存失敗時に回収するが、登録済み原本は保持する。
  同じreceiptを再使用した場合も、他のsourceが参照するファイルを削除しない。
  保存後の解析失効は保存自体のrollbackとはせず、旧workspaceの保存済み原本を残す。
- 音声取込は保存したMeetingのIDを直接返す。コピー/長さ読取中のscope変更を拒否し、
  新規コピーだけ回収する。従来の「取込中にproject削除→未分類へ保存」は維持する。
  InboxのURL受付/録音中待機/手動取込は、**保存成功時だけ**iOSのInbox原本を削除する。
  以前は失敗時も無条件に削除していたため、SQL失敗や読取不能時のデータ消失を修正した。
- 同期source削除もteam・復元・store保護を拒否し、SQLite成功前にmodel/fileを変えない。
  detachは既存storage guardを利用する。内部importとmutationを別extensionへ移し、
  UI変更と保存処理を分離した。既存の表示/選択枚数/ファイルサイズ上限は変更しない。
- 写真の選択状態は転送失敗時もリセットし、同じ写真を選び直せるようにした。
  native Picker自体は維持し、権限は選択した写真のみ。新しいOAuth/写真library権限はない。

検証:

- ホスト5スイートすべて成功（終了0）:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase5-import-final-quality/`。
  next-generationへ新規runnerを2本登録した。
- SourceImportの32 raceは取込前・実copy待ち・転送済み・登録後の4境界×8状態。
  generation/parent変更、team/復元/store保護/cancelに加え、実fileのSHA重複排除、
  SQLite ABORT/reopen/retry、登録済み共有ファイル保持、detach/delete拒否を確認。
  解析・音声とmodel stateはfixtureで、OSのPhotosPicker転送そのものではない。
- AudioImportは本番Import extension全体を実行し、8つの長さ読取待機race、
  削除projectの未分類保存、実SQL ABORT後のInbox保持/再試行、読取不能時の保持、
  録音中の待機queueを確認。本番Meeting codecでSQLite再読込一致。
  duration/media service・navigation/model stateはfixture。音声payloadも検証用で、
  実AV読取・再生・マイク・実録音の検証ではない。
- 新規fixtureの初期実行ではcancel例外の期待値、依存state不足、Meetingの
  rawAudioReference復元属性の比較で失敗した。期待値/fixtureを修正後に再実行し成功。
  不具合を隠すためにproductのcodecを変更していない。初期失敗を成功に合算しない。
  全体runnerの初回は出力オプション誤指定で終了2。正しい`--output-dir`で実行し直した。
- UI初回の2件は成功したが、再実行では写真Pickerの取消後に入力欄が見つからず1件失敗。
  trace/画面でLoading用のCancel操作中に実Pickerへ切り替わったことを確認した。
  写真タブと実ファイルnavigationの表示待ちを追加し、retry 0で再検証した。
  当該失敗ログは`.e2e/regression/phase5-import-final/`に残す。
- 最終Debug preview成功: `2026-10-23T08-42-09-c203c0d2.log`、既存警告11件。
  Release Simulatorビルドも成功: `2026-10-23T08-40-45-5535c1a7.log`、SDK 27.1、
  既存警告11件。ただしRelease要求後に写真選択のreset修正を入れたため、
  この古いRelease snapshotが最終変更を含むという前回の記述は撤回する。
  最終コードのDebug/UI検証とは区別し、次節でコード確定後にReleaseを再実行する。
- 修正後のUI E2Eは2シナリオを各2回、4実行/4成功。失敗/skip/中断/flaky 0、
  retry 0、model token/download 0。`.e2e/regression/phase5-import-post-review/report.json`。
  repeatを含む検出結果83件のうち、他79件はfilteredで未実行、成功には数えない。
  専用CoreSimulatorだけで、ユーザーのBitrig previewや実アカウントデータは使わない。
- 写真Picker、ファイルPicker、取消後の入力保持、Officeの一部解析済み表示を目視し、
  `import-native-photo-picker.png`、`import-native-file-picker.png`、
  `import-picker-cancel-retains-input.png`、`import-office-source-partial-coverage.png`へ保存。
  UI再設計のBefore/Afterではなく、最終コードの回帰画面であり他画面確認の代用ではない。
- 実装コミット`5718761`。詳細はPhase 5の`import-validation-summary.json`。
  mainのまま、push/上流の再取得/新しい実認証/外部送信は実施していない。
  性能の変更前後の新しい計測はなく、速度や電池改善の数値を主張しない。

実機確認やPhase 5全体の完了を意味しない。

### 右上音声Pickerとnative写真の失敗復旧（2026-10-23）

- CaptureMenuPopoverは保存先IDだけでなく、既存LocalImportContextを**Picker表示前**に
  保持する。選択結果はimportPickedAudio入口で再検証し、nil contextでも新しいscopeを
  暗黙取得しない。失効時は原本を変更せず、選び直す理由を既存のエラー表示へ渡す。
  右上作成・native popover/Picker・既存morph・メニュー構成は変えない。
- 本番音声入口の選択待ち8 raceとnil context拒否、正常なproject/global保存を追加。
  コピー後のduration待ち8 raceと、project削除後の未分類保存は引き続き成功する。
  実ファイル・本番Meeting codec・SQLiteを通すが、duration/mediaはhost fixtureのまま。
- 実写真を選ぶUI E2Eで、SQL登録失敗時に「ソースを追加」シートまで閉じる不具合を検出。
  写真/一般ファイルのsource登録だけに既存のpresentsErrorsLocallyを渡し、
  フォーム内で失敗を示して入力を保持するよう修正。scopeは同期storeProjectSourceだけ。
  copy/解析のawaitを囲まない。音声の独自エラーや解析後段の全体通知は変更しない。
- SourceImportの既存32 raceを再実行し、local/global両方の実SQL ABORTと後始末を検証。
  ローカル登録失敗直後の別保存は全体へ失敗通知されることも確認し、通知の抑止漏れを防ぐ。
- ProjectPhotoTransferとVisionを含む本番経路で、専用Simulatorの既定の風景写真を選択。
  SQL失敗後の入力/保存配列/ファイル保持、同一写真再選択での成功、SHA一致と重複排除、
  再起動後の再表示/SQLite一致/原本bytes一致を検証する。4つの外部権限はfalseのまま。
  当該写真はOCR文字がなく、保存済み・内容未取得と正しく表示される。
  任意画像の認識精度、画像全体のAI理解、実ユーザーの写真を試したという意味ではない。

検証:

- 最終Debug preview成功: `2026-10-23T08-58-20-6d59f50e.log`、既存警告11件。
  アプリコード確定後のRelease Simulatorビルドも成功:
  `2026-10-23T09-04-46-eb681d36.log`、SDK 27.1、既存警告11件。
  途中のRelease `2026-10-23T08-55-12-b7936a0c.log`も成功したが、
  登録エラー修正より前に要求したため、最終コードの証明には使わない。
- ホスト5スイートすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase5-picker-photo-quality/`。
  SourceImport 32 raceとAudioImport 16 race、SQL失敗のlocal/global通知を含む。
  Xcode test target未設定は変わらず、XCTest成功とは数えない。
- 最終UI E2Eは4実行/4成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase5-picker-photo-final/report.json`、model token/download 0。
  検出83件のうち他79件はfilteredで未実行。対象はnative写真の失敗/再選択/重複/再起動、
  Libraryの音声Picker取消/メモ作成取消（Light/Dark）、source Picker取消、Office取込。
- 初期写真E2Eは1実行/1失敗。登録失敗時にフォームまで閉じた実画面を保持した。
  local登録エラー処理の修正後は2回続けて写真E2E成功。途中の4件runは3成功/1失敗で、
  失敗はプロジェクト詳細にLibrary用の新規作成ボタンがあるというテストの誤った前提。
  その詳細には専用作成操作があるため、UIを変えずLibraryの実際の入口へテストを修正した。
  どちらの失敗も成功件数へ合算せず、元report/traceを残す。
- `photo-failure-before-dismissed.png`と`photo-failure-after-retains-input.png`を保存し目視。
  同じSimulator/失敗条件の別run（テスト用UUIDは異なる）で、画面全体の再設計や
  ピクセル比較ではない。再起動後の画像ソースは`photo-transfer-restored.png`へ保存し目視。
  `audio-picker-capture-light.png`/`audio-picker-capture-dark.png`も目視済み。
- 実装コミット`65229f6`、詳細はPhase 5の`picker-photo-validation-summary.json`。
  mainのまま、push/上流再取得/実認証/OAuth権限拡大なし。性能の新規実測はない。
  既存ネイティブUIと選択写真だけの権限範囲を保ち、エラー処理だけ既存部品へ接続した。

残り（Phase 5全体の完了とはしない）:

- 実機の選択写真・画像OCRの精度/失敗再試行、実AV音声読取/再生。
  native写真の実転送/保存失敗/同一写真再選択はSimulatorで検証したが、実機確認ではない。
- PDF/OCR/画像の実端末での範囲表示・失敗再試行、実YouTube通信と縮小画像の品質。
- 実バックアップ復元途中の中断UI E2E。hookのhost検証だけでは代替しない。
- 実native音声取込と復元の同時UI E2E、および復元完了をまたぐ実画面の確認。
  次節でhostの受付/世代境界を追加したが、実復元とnative音声の全組合せを証明しない。

### 復元と取込の排他・Picker世代境界（2026-10-23）

- `restoreBackup`の既存受付条件を本番`beginBackupRestore`へ切り出し、
  global音声取込、URL待機queue、取込URL、Inbox取込、ソース解析中の拒否を追加。
  元の録音/保存/AI job/保護/workspace/空判定の条件は維持し、キャンセル済みも拒否する。
  データがまだ配列へ追加されていないawait中にも、復元で保存先を入れ替えない。
- 全受付条件を通った時点だけで世代を更新し、復元前に開いたPickerを失効させる。
  復元が終了/失敗して`isRestoring`がfalseへ戻っても、旧Pickerは有効にならない。
  既存のBackupRestoreTransaction、SQLite構造、原本、UI、権限は変更しない。
- AudioImportChecksで16のbusy条件、team/protected/nonempty、キャンセル、
  実音声copy後の待機中の拒否/取込継続/SQLite reopen、旧Picker拒否と新Picker成功を確認。
  受付は本番extensionだが、空判定/model/navigation/media/backup error型はfixture。
  復元終了はフラグ解除でモデル化しており、ここで実restoreを完走したとは報告しない。
  別のBackupRestoreChecksでは本番package/transactionと実SQLiteの保存/rollback/再読込が成功。
- 実装コミット`b9e9ec6`。Debug preview成功:
  `2026-10-23T12-46-21-0feb9c11.log`、既存警告11件。
  実復元中断のUI確認は依然未完了。

## Phase 6: 外部連携（実施中）

### Notionの部分保存・接続変更（2026-10-23）

- 既存NotionServiceを再利用し、保存開始時のtoken/parentを一度だけ保持する。
  各transport直前と成功応答後に設定とキャンセルを確認し、途中で接続解除/変更された場合は
  新しいtoken/保存先へ置き換えたり、後続batchを送ったりしない。
  既に開始した外部リクエストを撤回できるという保証ではない。
- HTTP失敗だけでなく、作成後のtimeout/通信失敗/cancel/設定変更でも
  PartialPageFailureに作成済みpage IDとURLを残す。既存の手動保存/Ask AIの表示経路が
  ページへの導線と自動再作成しない説明を使えるようにする。新しい画面は作らない。
- 応答のpage IDをUUIDとして検証し、不正なIDをappendのパスに使わない。
  URLはHTTPS・hostあり・userinfoなしだけを案内に使う（Notion domainの認証ではない）。
  ID形式は[Notion公式Page参照](https://developers.notion.com/reference/retrieve-a-page)を確認。
  既存のAPI version `2022-06-28`、100 block分割、承認/料金説明、保存対象は変更しない。
- 設定供給/HTTP transportを差し替え、本番サービスのPOST/PATCH構築と
  失敗処理をホストテストへ登録。実タスク型を使い、別会議タスクは送らないことも確認。
  401/403/404/429/500/502、timeout/offline/cancel、不正JSON/ID/URL、接続変更/解除、
  明示的再接続を検証。create/appendを待機させて解除/キャンセルする4 raceも成功。
  Meeting/format、設定、HTTP応答はfixtureで、実Keychain/実設定/実URLSession/実Notionは使わない。

検証（復元受付とNotionの最終コードに共通）:

- Debug preview成功: `2026-10-23T12-52-12-700a0dc2.log`、既存警告11件。
  アプリソース確定後のRelease Simulator成功:
  `2026-10-23T12-57-30-0209f8ac.log`、iOS SDK 27.1、既存警告11件。
  最初のRelease要求は誤って`-platform`を渡し終了64（未ビルド）。
  `-destination 'generic/platform=iOS Simulator'`へ訂正して実行し直した。
- ホスト5スイートすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-notion-restore-quality/`。
  Notion/AudioImport/BackupRestoreを含む。Debug/Releaseログも同保存先へ保全した。
  Xcode test targetは未設定のままであり、XCTest/`bitrig test`成功とは報告しない。
- UI E2Eは3件ずつの2 run、合計6実行/6成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase6-notion-restore/report.json`と
  `.e2e/regression/phase6-notion-restore-navigation/report.json`。
  各runの検出83件のうち80件はfiltered。全83件を実行したという意味ではない。
  model token/downloadは両方0、実アカウントを使わない専用CoreSimulatorのみ。
  起動/再起動、Library/Journal/Ask AI切替、Tools、音声Picker取消とメモ作成取消の
  Light/Dark、写真/ファイルPicker取消と入力保持、Office取込/解析範囲表示を確認した。
- 目視済み回帰画像はPhase 6の`capture-regression-light.png`、
  `capture-regression-dark.png`、`source-office-regression.png`、`tools-regression.png`。
  UIを再構築していないためBefore/After比較ではない。Notionエラー画面は未目視であり、
  これらの画面で代替したとは報告しない。
- Notion実装コミット`f609ced`。mainを維持、push/上流再取得/OAuth scope拡大/実送信なし。
  新規の性能比較・実端末の入力遅延/スクロール/メモリ/電池測定は行っていない。
  詳細は`docs/qa/memora-1.0/phase6/notion-restore-validation-summary.json`。

### Gmailの即時解除・応答世代・失敗復旧（2026-10-23）

- 既存のGmailServiceではGoogleの失効応答を待ってからローカル状態を消していた。
  解除開始時に接続世代、キャッシュ、アカウント表示とローカル認証状態を先に破棄し、
  応答待ち中に新しいメール読取を始めない。解除中の重複解除/再接続も抑止する。
- Keychain削除失敗で残ったtokenを次の起動で使わないため、設定として解除markerを
  UserDefaultsへ保存する。新しいtokenのKeychain保存が成功するまで解除markerを戻さない。
  token自体やメールの本文をUserDefaultsへ保存しない。SQLite/既存記録の形式は変更しない。
- 接続開始時だけでなく新しいtokenを採用するときも世代を更新する。古いtoken更新/検索/
  本文/profile応答は新しい接続へ取り込まない。古いinvalid_grantは新しいtokenを削除しない。
  401では拒否されたaccess tokenだけを捨て、今回の操作はエラーで止める。
  次の明示的な読取でrefreshでき、一時的な5xx/通信失敗で連携を削除しない。
- callbackのscheme/path/state/code重複と空値、返却されたscope/有効期限/token、
  メールIDの単一パス要素と応答ID一致を確認。不正JSONや壊れた検索一覧を成功/空件にしない。
  明示limitを超えるmetadata取得も行わない。PKCEと既存read-only scopeは維持する。
- ブラウザとlive設定/通信だけを分離し、Gmail本体をhostで実行可能にした。
  native認証sheetはASWebAuthenticationSessionを維持し、取消時にcontinuationを1回だけ閉じ、
  古いcallback/取消が新しいsessionを終了しないようIDで束縛する。
  このnative sheetの実表示/取消は実OAuth未接続のため未検証で、ビルド成功で代替しない。
- [GoogleのOAuth案内](https://developers.google.com/identity/protocols/oauth2/native-app#tokenrevoke)
  で失効とinvalid_grantの扱いを確認。ローカル解除とGoogle側の失効完了は同じではない。
  送信/削除/下書き保存のscopeは追加しない。外部認証・実アカウント操作は行わない。

検証:

- 最終Debug preview成功: `2026-10-23T17-03-39-b1e0d3a3.log`、既存警告11件。
  アプリソース確定後のRelease Simulator成功:
  `2026-10-23T17-05-18-8171854a.log`、iOS SDK 27.1、既存警告11件。
  旧GmailServiceのanchor警告は分離したファイルへ移っただけで解消したとは報告しない。
- ホスト5スイートすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-gmail-quality/`。
  最後に追加した「接続sheet待ち中に開始した旧アカウント読取」のraceは、同じ本番コードで
  単独runnerも再実行し終了0（`gmail-final.log`）。Notionの共通gateへの移行も再実行成功。
  初回Gmail hostはテストの`precondition(await operation.value …)`がコンパイル不可で終了1。
  awaitをassert前へ分離して修正したもので、この未実行を成功に数えない。
- Gmailの認証/設定/保存/時計/HTTPはfixture。本番の接続/解除/refresh/read/parseは実行するが、
  実Keychain/UserDefaultsの耐久性、実プロセス再起動、実ネットワーク/Google応答ではない。
  解除markerがサービス再生成後も拒否されることはfixtureの保存状態を使う検証である。
  ASWebAuthenticationSessionのcallback/cancel自体はhostで動かしていない。
- UI E2Eは5実行/5成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase6-gmail/report.json`。検出84件のうち79件はfilteredで未実行。
  model token/download 0、専用CoreSimulatorのみ。Gmail未設定の理由/接続無効/アカウント不在の
  Light/Dark、Library起動/再起動、Library/Journal/Ask AI切替、Tools、音声Picker取消を確認。
  この未設定ビルド用テストは将来OAuthを設定する環境では分離が必要。
- `gmail-unconfigured-light.png`と`gmail-unconfigured-dark.png`を保存し目視済み。
  回帰画像でありUI再構築のBefore/Afterではない。実OAuthや各エラー状態を見た意味ではない。
- 実装コミット`fc1075a`。mainを維持、push/上流再取得/OAuth scope拡大/メール送信なし。
  新規の性能比較・端末の入力遅延/スクロール/メモリ/電池の計測はなし。
  詳細は`docs/qa/memora-1.0/phase6/gmail-validation-summary.json`。

### MCPの会話世代・権限変更・一覧復帰の保護（2026-10-23）

- 本番MCPの一覧取得/実行を、`MCPAgentExecutionContext`で開始時のworkspace、
  workspace世代、request/message ID、選択policy、MCP権限世代へ結び付けた。
  既存`isCloudSessionAuthorized`を再利用し、出典・memory・calendar許可が現在有効か再確認する。
  contextが古くなった処理は、新しい会話のactive tool一覧/trace/blocked状態を更新しない。
- 各サーバーの設定/認証世代/tokenを取得前後に検証し、全件取得後にも再filterする。
  後続サーバーのawait中に無効化された先行サーバーのツールを一覧へ戻さない。
  未知料金は従来どおり確認済みcacheだけを使い、無料と確認したものだけネットワーク取得へ進む。
- 承認後、SDK接続準備の後、SDK呼出前、結果の利用前に現在の権限を確認するcallbackを
  本番Provider/Clientへ渡す。Clientは各ページ/ツール結果で接続世代も確認し、
  古い取得結果でcacheを更新したり、古い失敗が新しい接続をforgetしたりしないようguardする。
  開始済みの外部操作の取消や、HTTP送信との原子的な同期を保証するものではない。
- MCPのOFF→ON、サーバー設定の変更→復元、再認証でも一時的な世代を更新する。
  世代/承認は保存・復元しない。SQLite形式、既存データ、UI/メニュー、料金/権限の範囲は維持。
- Hostは本番のMCP extension、Context、Registry/Provider、設定/ON-OFF操作、利用回数制限を実行。
  承認待ち/接続準備待ち/結果待ち各21変更、計63 raceが成功した。
  一覧取得中の20変更、後続サーバー待ち中の先行サーバー失効、cache-only、承認拒否、
  50回上限、実SQLite ABORT/再読込、timeout/認証/権限/回数エラーの秘匿も成功。
- Model状態/既存出典許可gateの返値/承認/Keychain/MCP SDK clientはfixture。
  hostの準備待ちは模擬SDKの待機点で、実接続/HTTP/OAuthではない。
  本番MCPClientのguardはBitrigでcompile/linkと静的配線チェックを行ったが、
  実SDKの複数ページ/再接続/timeout/cancel/cacheのruntime検証とは区別する。
  `authorizeMCPServer`の実認証後の世代更新もビルドのみで、実OAuth完走は未検証。

検証:

- 最終Debug preview成功: `2026-10-23T17-45-08-84705f64.log`、既存警告11件。
  最終アプリソース確定後のRelease Simulatorも成功:
  `2026-10-23T17-46-37-d13535c0.log`、iOS SDK 27.1、既存警告11件。
- ホスト5スイートすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-mcp-context-quality/`。
  SDK OAuth policy、Calendar interface/編集policy、Gmail/Notionの既存チェックも成功。
  これは実Google/EventKit/MCPサーバーの接続成功を意味しない。
  初回MCP hostはテストのthrowing decodeをprecondition内で呼びコンパイル失敗（終了1）。
  decodeをassert前に移して修正した。初期の未実行は63 raceの成功へ合算していない。
  Xcode test targetは未設定のままであり、XCTest/`bitrig test`成功とは報告しない。
- UI E2Eは5実行/5成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase6-mcp-context/report.json`。検出85件のうち80件はfilteredで未実行。
  model token/download 0、専用CoreSimulatorのみ。起動/再起動、Library/Journal/Ask AI切替、
  Tools、Gmail未設定のLight/Dark、MCP未接続/追加フォームのLight/Darkと取消を確認。
  MCPの接続確認・保存・認証は操作せず、偽の接続済み状態を作っていない。
- `mcp-unconnected-light.png`/`mcp-unconnected-dark.png`と
  `mcp-unsaved-editor-light.png`/`mcp-unsaved-editor-dark.png`の4枚を保存・目視済み。
  SecureFieldはrunnerの自動秘匿マスク（黒い領域）で、tokenは入力していない。
  UI再構築のBefore/Afterではなく回帰画面。承認中/実行中/実エラー画面を見た意味ではない。
- 実装コミット`ce98f4f`。main維持、push/上流再取得/実認証/外部操作/課金なし。
  新しい性能比較・端末の入力遅延/スクロール/メモリ/電池測定はなし。
  詳細は`docs/qa/memora-1.0/phase6/mcp-context-validation-summary.json`。

残り（Phase 6全体の完了とはしない）:

- Calendarの状態遷移の追加監査・fixture検証、MCP SDK/transportの実接続・複数ページ・
  接続変更・timeout/cancelのruntime検証。Gmailの実OAuth/sheet取消/Google失効完了と
  実メールの表示/解析も未検証。ローカル解除だけで外部側の失効を確認済みとしない。
  実認証/OAuth scope拡大や実メール送信は実施しない。
- 今回のGmail検証は接続/account世代の境界であり、agentのworkspace/privacy/plugin OFF変更を
  await中にすべて検証した意味ではない。外部取得からAI送信までの追加監査は継続する。
  MCPも完了済みの取得結果を後続モデル送信に載せる全期間の権限bindingは追加監査が必要。
  今回のMCP操作中のgateで、全サービス/全送信経路の安全性を完了とはしない。
- Notionの実token失効/権限変更/通信/作成済みページ内容/エラー表示は実サービス未検証。
  設定が検証点の間にA→B→Aと戻る変更は、世代付き設定ではないため検出できない。
  この修正は接続token/parentの境界であり、agentのworkspace/record/plugin設定について
  await中の全状態変化を包括的に保証するものではない。
- Notion API versionの移行、長い単一rich_textの分割、外部サービス側の実料金/上限は別課題。

### MCP取得済み結果の後続利用を権限へ結び付ける（2026-10-23）

- `MCPResultAuthorization`と既存の会話contextを再利用し、成功したMCP結果を
  開始時のworkspace世代/request/message、選択policy、MCP権限世代、サーバー設定、
  認証世代、Bearer tokenのfingerprint、ツールfingerprintへ一時的に結び付けた。
  token本文をgrantへ保存しない。grantは最大24件で、新しいagent依頼時に破棄する。
- `isCloudSessionAuthorized`から同じgrantを確認するため、取得後の変更でも既存の
  次モデル要求/stream表示/承認/資料生成gateが停止する。contextの基本bindingと
  cloud出典gateを分離し、結果grantによる再帰呼出しを避けた。
  既に開始した外部操作/モデル送信を取り消すものではなく、ネットワーク送信との原子的同期でもない。
- 会話のmessageには一時IDのみを持たせる。grant消失/未知IDは拒否し、後続呼出しで
  古い許可を新しい許可へ置換しない。結果を利用した回答は既存のprovenanceを不完全とし、
  履歴経由の外部AIへの自動再利用を許可しない。SQLiteの会話codecはID/grantを保存・復元しない。
  既存データ形式、UI、Liquid Glass、作成/コンポーザー位置、外部サービスの権限範囲は変更なし。
- Hostは取得完了後の21状態変更にgrant消失/未知IDを加えた23ケースと、それぞれで
  再呼出ししてもdispatchが増えないこと、保持上限、別ツール待ち中のbatch拒否、
  次モデル応答待ち中の停止を本番会話ループで確認した。
  `PersonPrivacyChecks`は本番cloud出典gateがMCP gateの拒否を尊重すること、
  snapshot codecはgrant IDを保存/復元しないことを確認する。
- MCP hostのmodel/既存cloud許可/承認/Keychain/SDK transportはfixtureのまま。
  PersonPrivacyのMCP predicateもbool fixtureであり、全model送信と実MCP SDKを
  一体で実行したE2Eとは区別する。実API/認証済みアカウント/実課金は操作していない。

検証:

- Debug preview成功: `2026-10-23T21-22-00-00bb09b0.log`、既存警告11件。
- 最終アプリソース確定後のRelease Simulator成功:
  `2026-10-23T21-23-51-fefbfb5d.log`、iOS SDK 27.1、既存警告11件。
- ホスト5スイートすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-mcp-results-quality/summary.json`。
  新規MCPの23ケースと会話ループ2ケース、既存の63操作中race/20一覧変更、
  source/privacy/会話保存/Calendar/Gmail/Notion/資料/SQLite失敗の既存回帰も成功。
  最終テスト差分追加後のMCP単独runnerも終了0。Xcode test targetは未設定であり、
  XCTest/`bitrig test`成功とは報告しない。
- UI E2Eは5実行/5成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase6-mcp-results/report.json`、run `01a168b7-b72d-7664-99ca-b0ffd004dbc5`。
  85検出のうち80はfilteredで未実行。model token/download 0、専用CoreSimulatorのみ。
  起動/再起動、Library/Journal/Ask AI切替、Tools、Gmail未設定、MCP未接続/追加取消を確認。
- `mcp-results-unconnected-light.png`/`mcp-results-unconnected-dark.png`と
  `mcp-results-unsaved-editor-light.png`/`mcp-results-unsaved-editor-dark.png`を保存・目視済み。
  SecureFieldはrunnerの秘匿マスクで、tokenは入力していない。
  UI変更のBefore/Afterではなく回帰画像。実接続済み/実行中/失効時の画面確認ではない。
- 実装コミット`57619a3`。main維持、push/上流再取得/実認証/OAuth scope拡大/外部操作なし。
  新規の性能比較は行っておらず改善率は報告しない。実Keychainを含む追加gateの負荷、
  入力遅延/スクロール/メモリ/電池は端末で未計測。
  詳細は`docs/qa/memora-1.0/phase6/mcp-results-validation-summary.json`。

残り:

- Phase 6は継続中。Gmail/Notionの取得/保存から後続AI利用までのworkspace/privacy/plugin
  境界、Calendar状態遷移の追加監査、実MCP SDK/transport/OAuthのruntime検証は未完了。
- 実機の録音保持/中断復旧/復元、Phase 7、端末性能計測も未検証のまま。
  このMCP単位のローカル成功を全サービス/全Phase完了とはしない。

### Gmailの承認・取得・後続利用を同じ会話に限定する（2026-10-23）

- Gmailの承認/検索/本文取得を`MemoraModel+GmailTools`へ集約。
  MCPと共通の`AgentConversationExecutionContext`でworkspace/世代/request/message/policyを
  確認し、Gmail固有のON/OFF世代と接続世代/アカウント/現在のtool・plugin許可を重ねる。
  一時grantには認証tokenやメール本文を保持せず、最大24件、次のagent依頼で破棄する。
  連携設定の更新処理も共有extensionへ移し、既存MCPの世代更新を維持した。
- GmailServiceへ許可callbackを渡し、取得開始、refresh完了後のメール送信前、
  各HTTP応答後に検証する。先頭metadata取得中の失効で2件目以降を取得しない。
  古い会話の結果/件名をtraceへ反映しない。承認拒否・取得失敗時は同じ依頼のメール再実行を拒否する。
  承認文言、料金未確認の毎回承認、自動jobのGmail拒否、read-only OAuth scopeは維持。
- 取得成功後もgrantをcloud出典gateに結び付け、後続のモデル要求/表示/資料生成を検証する。
  端末内AIではtool callback前後/最終回答と、共通の承認前後/資料生成にもgateを追加。
  会話codecは一時IDを保存・復元せず、cloud結果のprovenanceを不完全として履歴の自動再送を防ぐ。
- メール取得の401/403は保持済み結果の接続世代を失効させる。接続設定は残し、
  新しい依頼での明示的なrefresh/再取得を可能にする。429/5xxとは区別する。
  サインイン中の任意profile取得は対象外とし、profileの401/403が接続完了時の
  `isWorking` cleanupを妨げないことも検証した。
- UI/ナビゲーション/Liquid Glass/SQLite形式・既存データは変更なし。
  OAuth scope拡大、実認証、実メール取得/送信、課金、push、上流再取得は行っていない。

Host検証の範囲:

- 承認/refresh/一覧/先頭metadata/full本文の5待機点でcloud 14変更・compact 13変更、
  合計135 raceが成功。workspace/世代/request/存在/終了/復元/保護/policy/plugin可用性/
  Gmail OFF・OFF→ON/切断/同じメール名での再認証、cloud既存出典gate拒否を含む。
- 取得後31ケース（grant消失/未知IDを含む）と再呼出し拒否、24件上限、
  別tool待ち中のbatch拒否/次のモデル応答待ち中の停止、承認拒否/cancel/HTTPエラー、
  401/403による結果失効と429/5xxの区別、profile拒否時の接続完了を確認した。
- 本番GmailService/取得extension/結果context/Registry/会話ループ/連携ON-OFF更新を実行する。
  会話状態/Registry組立/plugin可用性/承認UI/設定・Keychain/browser/時計/HTTPはfixture。
  compactは本番取得gateを通すが、Apple LanguageModelSessionはhost実行しておらず、
  callback/最終回答への配線は静的検査とビルドで確認する。
- 本番cloud出典gateがGmail拒否を尊重すること、cloud/端末内の資料生成と承認前後の拒否は、
  既存のPerson/Artifact/Calendar runnerからGmail bool fixtureを使って別途検証した。
  全送信経路/実Google/実Keychain/browser/認証済みUIの一体E2Eではない。
- 初回Gmail agent runnerは、再認証の模擬通信も同じgateで待たせたためcontinuation警告で停止。
  対象のhost子プロセスをSIGTERMで終了143とし、gateを1回だけ待たせるfixtureへ修正。
  初期未完走は成功に数えていない。初期Debugで生じた`.shared` default引数のactor警告も、
  serviceを呼出元から明示的に渡すことで解消した。

最終検証:

- 最終アプリソースを含むDebug preview成功: `2026-10-23T21-46-30-24b60ca2.log`。
  Release Simulatorも成功: `2026-10-23T21-46-52-021c927c.log`。
  iOS SDK 27.1、各11件の既存警告。以後アプリソースは変更していない。
- ホスト5スイートすべて終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-gmail-context-final-quality/summary.json`。
  最後のprofile除外guard追加後、GmailService/GmailAgent runnerも別途再実行して終了0。
  cloud/端末内の資料生成/承認gateはArtifact/Calendar runnerでも個別に検証済み。
  Xcode test target未設定のため、XCTest/`bitrig test`成功とは報告しない。
- 最終DebugでUI E2Eを5実行/5成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase6-gmail-context-final/report.json`、
  run `01a168ce-ad74-768a-9e1a-bb3c5b017399`。85検出中80はfilteredで未実行。
  model token/download 0、専用CoreSimulatorのみ。起動/再起動、Library/Journal/Ask AI切替、
  Tools、Gmail未設定、MCP未接続/未保存取消を確認した。
  中間ソースのE2E5成功はこの最終5件に加算しない。
- `gmail-agent-unconfigured-light.png`/`gmail-agent-unconfigured-dark.png`を保存・目視済み。
  UI変更のBefore/Afterではなく回帰画像。実接続/承認中/実エラーの画面確認ではない。
- 実装コミット`0d69fbf`、main維持、pushなし。
  詳細は`docs/qa/memora-1.0/phase6/gmail-agent-validation-summary.json`。

残り:

- Phase 6は継続中。Notionの外部保存をまたぐworkspace/privacy/plugin境界と設定ABA、
  Calendarの追加状態監査、実Gmail OAuth/失効/再認証、実MCP SDK/transportは未完了。
- 今回は比較時点での状態とGmail ON/OFF・接続世代を検証しており、全plugin catalog編集が
  検証点の間に一時変更→元へ戻るケースを包括的な世代監視で覆ったものではない。
  手動の用語集取り込みなど、agent以外のGmail利用経路のworkspace境界も別途確認が必要。
- 既に開始した外部操作/モデル送信の取消や、送信との原子的同期は保証しない。
  端末内モデルが既に受け取った内容を後から消すこともできない。
- 性能改善の実測は追加していない。保持済みgrant確認に伴うplugin/registry検証の負荷、
  実機の入力遅延/スクロール/メモリ/電池、録音保持/中断復旧、Phase 7は未検証。

### Notionの外部保存を承認済みsnapshotと現在の権限へ限定する（2026-10-23）

- `NotionExportContext`で会議と外部送信を許可した関連タスクを固定し、会議詳細の手動保存と
  AI保存で同じ送信検証を再利用した。private/別会議のタスクは送らず、承認中に増えた
  タスクも勝手に追加しない。編集/削除/送信許可、workspace世代、復元/保護を各batchで確認する。
- Agentは既存の`AgentConversationExecutionContext`と新しいNotion固有contextを重ね、
  request/message/policy、plugin/registry、Gmail由来の許可、Notion ON/OFF世代も検証する。
  送信対象を既存cloud/artifactの出典へ記録し、後続の通常出典gateでも変更を検知する。
  旧会話は新しいtrace/blocked状態を更新せず、失効結果のページURLをモデルへ渡さない。
- NotionServiceは各POST/PATCH直前と応答後にMainActorの許可callbackを確認する。
  UIからのtoken保存/削除と親ID編集で一時世代を更新し、A→B→Aも検知する。
  設定世代はlockで保護し保存しない。設定値/既存SQLite形式/既存データは維持した。
- 「Ask AIで利用する」OFFは手動保存の禁止ではないため、Notionの利用OFF世代は
  agent側だけで確認する。手動保存にも記録の外部送信許可と保存先の検証は必須。
  この区別をレビューで修正し、手動保存が残ることを正のケースで確認した。
- ページ作成後の中断は既存`PartialPageFailure`でID/URLを保持し、後続batchを止める。
  所有中の元会話には復旧用のローカルtraceを残すが、別会話へは渡さず、自動再作成しない。
  保存完了後、呼出元へ戻る直前に状態が変わった場合も実行中表示を残さず停止扱いにする。
  これは永続的な受領票/再起動後の復旧一覧ではなく、workspace変更後の自動転記もしない。
- 手動保存のalertは元workspace/世代だけに表示する。token保存/削除に失敗した場合は
  入力/接続状態を消さず、既存フォームにnative alertで失敗を表示する。
  SwiftUI指針に沿ってnative入力とView identityを維持し、親IDの失効処理だけを同期setterへ追加。
  `onChange`の通知coalesceで一時変更を取り逃がさないための局所的なbindingであり、UI再構築はない。

Host検証の範囲:

- Agentはcloud 24変更・compact 23変更 × 承認/create/中間append/最終appendの4待機点、
  計188ケース。手動は記録/タスク/workspace/設定の15変更 × 3待機点、計45ケースが成功。
  中間の「手動でもAsk AI OFFを拒否」の51ケースは最終45ケースへ合算しない。
- 承認拒否/cancel/HTTP 401/403/429/500、既知ページID/URL、同じ依頼の再実行拒否、
  送信対象の正確な選別、承認後に増えたタスクの除外、設定ABA、設定保存/削除失敗の旧値保持も確認。
- 本番Service/export/agent context、共有会話binding、privacy/registry、連携ON/OFF処理を実行する。
  Meeting形状/model state/registry組立/承認UI/Keychain/設定供給/HTTPはfixture。
  実Google/Notion、実Keychain、URLSessionネットワーク、認証済みUIではない。
  recordCloudReadsの組立はfixtureであり、実cloud出典gateやSQLiteの既存回帰とは別の境界として扱う。
- 最初の新規hostは`AIAnswerFailure.swift`を検証用コンパイル対象に含め忘れ、終了1で未実行。
  runnerへ実ファイルを追加して修正した。未実行を成功へ数えていない。
- 最初のUI E2Eは4成功/1失敗。親IDの消去自体は成功していたが、空欄のAX valueが
  placeholderになるiOSの挙動へ空文字列を期待していた。trace/画像を確認し、
  以前の入力値が消えたこととplaceholderを確認する期待へ修正した。
  この失敗と未到達のDark後半を成功には数えず、別runで再実行した。

最終検証:

- Debug preview成功: `2026-10-23T22-46-18-06c4f4e8.log`。
  Release Simulator成功: `2026-10-23T22-46-20-d6c6a1ee.log`。
  いずれも最終アプリソースを含み、以後ソース変更なし。iOS SDK 27.1、既存警告11件ずつ。
- ホスト5スイート終了0:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-phase6-notion-context-final-quality/summary.json`。
  最終の状態表示調整後にもNotion単独runnerを再実行し終了0。
  Xcode test target未設定のためXCTest/`bitrig test`成功とは報告しない。
- 最終DebugでUI E2E 5実行/5成功、失敗/skip/中断/flaky 0、retry 0。
  `.e2e/regression/phase6-notion-verified/report.json`、
  run `01a16905-f3d1-7374-8d6c-64ca322b71f7`。86検出中81はfilteredで未実行。
  model token/download 0、専用CoreSimulator。起動/再起動、Library/Journal/Ask AI、Tools、
  Gmail未設定、Notion未設定のLight/Dark、親IDの編集/再起動後復元/消去を確認。
  親IDの非秘密テスト文字列を消去しており、token保存/削除や実サービス接続は操作していない。
- `notion-context-unconfigured-light.png`/`notion-context-unconfigured-dark.png`を保存・目視済み。
  SecureFieldの黒い領域はrunnerの秘匿マスクで、tokenは入力していない。
  通常フォームの回帰画像であり、UI変更のBefore/Afterや失敗alertの実行確認ではない。
- 実装コミット`c8eefc6`。main維持、push/上流再取得/実認証/外部保存/実課金なし。
  詳細は`docs/qa/memora-1.0/phase6/notion-context-validation-summary.json`。

残り（Phase 6全体の完了とはしない）:

- 実Notionの接続/権限変更/timeout/ページ描画と、実Keychain失敗alertの実行確認。
  設定世代はアプリの更新経路を覆うが、他プロセス等から直接書き換わる全経路のABA保証ではない。
- 部分保存の永続受領票/再起動後復旧一覧、完了済みNotion URLを保持した後の全モデル送信期間の
  接続bindingは追加監査が必要。既に始めた送信を取り消したり、送信と検証を原子的に同期したりはしない。
- Calendarの追加状態監査、Gmailの非agent経路、plugin catalogの一時変更→復元、
  実MCP SDK/OAuth、実機の録音保持/中断復旧/復元、Phase 7は未検証のまま。
- Notion API version/長文rich_textの扱い、現行設定欄のdatabase表現とpage保存実装の文言整合は残る。
  本修正でdatabase保存を追加したり、既存API versionを移行したりはしていない。
- 新しい性能比較は行っていない。多数のタスクを持つsnapshot検証の負荷、
  実機の入力遅延/スクロール/メモリ/電池は未計測で、改善率は報告しない。

## Phase 7

視覚・アクセシビリティ・IME・Reduce Motionの最終確認、思考ロゴの調査は未完了。

### 2026-10-23 利用者指定のUI改善（既存の未完了項目は継続）

- サイドメニューの未サインイン表示を削除。設定のアカウント導線、プラン、設定ギアは維持。
- ワークスペースをプルダウンではなく、選択中がチェックで分かる一覧へ変更。
- サイドメニューと設定の外部レコーダー入口を統一。Omi直接接続/機器詳細を維持し、
  PLAUD・他社レコーダー・ボイスメモの音声取込へ到達できるようにした。
  他社Bluetooth直接接続は未対応と表示。既存のworkspace拘束付き音声保存経路を再利用。
- Ask AI新規チャット上部へエージェントの作業提案を追加。端末内の実際の許可済み記録と
  未完了タスクから作り、サンプルは除外。根拠がない場合は汎用提案とし、パーソナライズを装わない。
  選択時に再検証して下書きへ入れるだけで、送信・LLM呼出・承認は自動実行しない。
  既存の下書き・添付がある時は提案を無効化して保護。
- コンポーザーの＋はガラスの円を除去し44pt操作領域を維持。押下後は独自Popover/zoom/
  固定遅延ではなく標準MenuのLiquid Glassに委ね、5つの既存アクションを保持。
- iOS 27.1 SDKでDebug preview/Release成功（既存警告11件）。ホスト5スイート成功。
  最終UI E2Eは8/8成功、失敗/skip/flaky/interruptedは各0、retry 0。
  全89件のうち残り81件は今回未実行で、成功に含めない。
- 実画面のLight/Dark、最大文字サイズの折返し/スクロール、Reduce Motion時のMenu開閉を確認。
  証拠と失敗→修正履歴、実機/実ファイル/VoiceOver/IME/性能の未検証範囲は
  [UI改善の検証記録](qa/memora-1.0/agent-entry/README.md)を参照。
  他社Bluetoothプロトコル追加、外部認証、実課金、全フェーズ完了とはしていない。

## 次の優先順位（今回の検証では完了としない）

- P0（公開前）: 実機の録音保持/中断復旧/音声取込と、復元中断のデータ保護。
  外部保存をまたぐworkspace/privacy/権限変更の追加監査・回帰。
- P1: Calendarの追加fixture検証、MCP SDK/transportのruntime検証、Gmailの実OAuth境界、
  Phase 7のVoiceOver/Dynamic Type/IME/Reduce Motion/実画面確認、端末性能計測。
- P2: Notion API version移行と長文block分割、意味的スキル選択、独立した思考ロゴ部品。
  いずれも実接続や追加料金が必要な部分を無断で有効化しない。
