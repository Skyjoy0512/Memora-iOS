# 性能最適化の記録

基準コミット: `18a65ec73fc94957c65e6289258f21ada4990c09`。GitHub `main` と一致を確認し、未コミット変更がない状態から開始。既存UI・アニメーション・保存形式を維持する。Project.json、権限設定、バックアップ形式、録音処理は変更しない。

## 調査と採用判断

| 対象 | 観察された処理 | 改善方針と安全条件 | 比較方法 |
|---|---|---|---|
| PerformanceLog | 1計測ごとに最大500件をJSON化・SQLiteへ保存 | 即時表示は維持し、診断ログだけ1秒の固定窓でまとめる。失敗時のrevisionを保持し、背景移行・リセットは同期確定。業務保存のキューと原子性は維持 | 本番logger/queue、隔離backend、500件保持中の100件burstを21回 |
| LibraryView | 各レコードに対し既存セクションを線形検索 | キーから配列位置への辞書を併用。最初に現れたセクション順、分類・タイトル・レコード順はそのまま | 旧メソッドを基準から抽出し0/1/100/1000件、昇順・降順・タイトル順の完全一致 |
| AI ranking | 会議ごとに全タスクをfilter | 質問ごとに一度だけ会議IDでgrouping。完了タスクも含む元の得点・同点順・fallbackを維持。質問をまたぐ権限キャッシュは作らない | 旧実装と順位の完全一致、100/1000件・各2タスク |
| MediaImageCache | 同一キーのmissが並行デコード、個数制限のみ | 要求を共有、実デコードbytesで64MiB/80件に制限、memory warningで解放。サイズ・ImageIOオプション・画質は維持。削除済みファイル、取消・古い要求は表示しない | DEBUG私有画像で同一UIImage・解像度・取消・削除を検証 |
| SummaryPreviewCache | UUID辞書が無制限にsummaryを保持 | thread-safe NSCacheを500件/8MiBで制限。summary完全一致条件を維持し、eviction後は再計算 | DEBUG同一IDの本文変更・clear後の結果一致 |
| Home/Journal | 日付ごとの集計とタイムラインに全記録を再度渡す | Phase 2で入力を狭める条件・カレンダーの関連範囲を調査 | 過去・今日・未来・時差・イベントの回帰fixture |
| ProjectSearchIndex | 反復質問でも全資料をJSON encode/hash、SQLite更新transactionを開始 | Phase 2でbounded inputの完全一致を用い、変更資料のみ再計算。権限・削除・プロジェクト境界・送信前/保存前確認を保持 | 実SQLite FTS5、更新・削除・再open・境界・反復100/1000資料 |
| LocalStore | 同じSQLを各documentごとにprepare/finalize | Phase 3でロック内のstatement再利用を検討。rollback・更新時刻・保存順序は維持 | 隔離SQLiteのbatch・旧bytes・失敗・順序 |

## 測定条件

ホストApple Silicon上でSwift `-O`、同じfixture、21回、ContinuousClock。中央値は11番目、p95は20番目、最大は21番目。これはCPU処理単位の比較であり、iPhoneのRelease実測ではない。生データ・音声・APIキーは使用しない。実行用一時ファイルは実体パス `/Volumes/WorkspaceSSD/Development/Temp/memora-performance-20261013` に隔離。

`python3 tools/checks/run-performance-checks.py --before` / 同コマンドの`--before`なしで再実行可能。logger比較のbackendはメモリ上の隔離fixtureであり、時間はJSONとqueue処理を含み、SQLiteディスク待ちは含まない。索引benchmarkは本番ProjectSearchIndexと隔離SQLiteを使用。

Phase 1の初回測定（並行ビルド中のばらつきがあるため最終比較で再測定する）:

| 処理 | 変更前 中央値/p95/最大 ms | Phase 1 中央値/p95/最大 ms |
|---|---:|---:|
| AI順位 100件 | 0.986 / 1.069 / 1.087 | 0.938 / 1.143 / 1.183 |
| AI順位 1000件 | 41.777 / 43.254 / 43.604 | 6.080 / 6.116 / 6.141 |
| 日付分類 100件 | 0.321 / 0.336 / 0.344 | 0.344 / 0.455 / 0.458 |
| 日付分類 1000件 | 2.630 / 2.670 / 2.680 | 2.501 / 2.548 / 2.562 |
| 100ログburst（500件保持） | 73.495 / 76.543 / 79.156 | 1.352 / 1.877 / 1.984 |
| burst 21回の保存数 | 2100 | 21 |
| 索引反復 100資料（基準） | 4.124 / 5.190 / 5.398 | Phase 2で比較 |
| 索引反復 1000資料（基準） | 34.110 / 35.580 / 35.999 | Phase 2で比較 |

## 検証状況

- 基準ビルドとPhase 1の最初のビルド成功。既存AppIntents metadata warning 1件。
- CollectionPerformanceChecks: 旧検索順位・セクション構成と一致、0/1/100/1000件、空クエリ/不一致、未所属・複数タスク。
- PerformanceLogChecks: 500件上限、中央値/p95/最大、保存の往復、失敗後retry、古いqueued保存を待つresetが成功。
- RecordStoreFailureChecks: async rollback、並行failure injection、同期復旧が成功。
- tools/checks/run-tool-integration-checks.sh: 4 suite成功（tool registry、Web検索intent、provenance、MCP OAuth）。
- DEBUG Performance caches: 同時要求8件の同一UIImage、120pxの解像度、取消済み要求、削除後のcache miss、summary編集とclear後の一致が成功。既存Main navigation自己チェックの古い期待値を現行Home/Library/Ask AI順に修正（実UIと既存RootNavigationChecksはその順を実装済み）。
- UI: 初期HomeのAX情報を取得。基準画面の操作中に再buildでAXが失効したため、画面全体の変更前後pixel比較は未実施。変更したViewはコレクション処理・取消guardのみ。Liquid Glass/FAB/遷移/Navigation/safeAreaのコードは変更しない。

未測定: 起動〜実際に操作可能、Home表示完了、タブ遷移時間、iPhone ReleaseのCPU/アイドル/ピークメモリ、SwiftUI再描画回数、frame drop/Animation Hitches、画像decode時間の変更前後。これらを処理単位benchmarkの数値で代用しない。

## Phase 2

- TaskOwnershipはリストの本人名を1回だけ正規化。Home/日別サマリーのownTasksを再利用し、本人名変更・明示owner・未所属判定は従来通り。
- JournalTimelineBuilderはイベントIDごとに会議を1回groupingする。各groupの元の順序と12時間の一致条件を維持し、日付外に開始した録音も従来通り照合する。タイムラインのIDやView階層は変えない。
- Homeのカレンダー読取はリクエストID・日付・対象カレンダー・設定・取消を回答後に再確認する。古い日付の遅い応答が現在の日付へ上書きしない。表示するイベントが同じときには再代入しない。
- ProjectSearchIndexは既存の200,000文字/block・2,000,000文字/projectの境界を維持し、同じプロジェクトの完全に同じ確定済み入力だけ同期を省く。変更資料だけsorted JSONとSHA-256を再計算。削除・所属解除・permissionでの入力減少・プロジェクト変更・memory clearで再同期する。transaction失敗時は新cacheを採用しない。重複targetは旧順次処理を維持する。
- ProjectContextの現在の許可対象だけを索引/fallbackへ渡す。AI送信前・応答保存前のprojectEvidenceStillAvailableは変更せず、本文ファイルを引き続き実読取する。
- ProjectContextBuilderは1リクエスト内だけ同じタイトルの2-gramを再利用。検索の得点・順位・ページ・時刻・引用番号は同じ。

採用しなかった日付index: 1000件の元の日付filter中央値0.004msに対しwarm index0.001ms、100件は0.001→0.002ms。初期grouping・無効化・position管理を増やすほどの効果が無いため削除。JournalDailyRecap/RecapContextの文章・計算は変更しない。

所有者判定1000件の初回比較: 2.507/2.678/2.697ms → 0.354/0.371/0.371ms（中央値/p95/最大）。最終表では静かな環境で再測定する。

ProjectContextChecks・ProjectSearchIndexChecks・HealthReviewLoaderChecksが成功。索引の同一入力、再open、更新、permission相当の入力除外、削除後の再作成、cache clear、プロジェクト境界、ページ/時刻、Unicode境界を追加検証する。HomeのAsync処理を含むUI/DEBUG回帰はPhase 2ビルド後に確認する。
