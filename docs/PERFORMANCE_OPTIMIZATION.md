# 性能最適化の記録

## 2026-10-14 AI／Widgetの追加に伴う制約

- 本物のストリームは最初の本文を即公開、その後は最短100msでまとめる。
  途中の文章でMarkdown／構造化UIの再レイアウトをしない。プロジェクトの
  途中本文は専用leafで読み、SQLiteへトークンごとに保存しない。
- Native UIは32KiB／8部品／各30項目、MCP候補は16件／24KiB。
  候補検索は端末内で、外部embeddingや追加LLMを呼ばない。
- Widgetは既存記録の最小snapshot。350msでまとめ、プロジェクトのタスク
  件数は一度で集計。ExtensionはSQLiteを開かず64KiB以内のファイルだけ。
- 上記は設計上の負荷制限。起動時間・初回応答時間・frame／メモリの
  実機改善率は未測定。本文書の従来のキャッシュ・保存順序は変更しない。
- 構造化UIでは、全記録のcloud grant集合とメモリ指紋を含む参照確認を
  各行で繰り返さず、1描画で1度に集約。実際にUIが使うタスクIDだけを
  フィルタし、出典は辞書化。質問を越える権限キャッシュは作らず、タップ／
  遷移／承認前は再確認する。コード上の重複処理を除去したが、実機の
  フレーム改善率は計測していない。

基準コミット: `18a65ec73fc94957c65e6289258f21ada4990c09`。GitHub `main` と一致を確認し、未コミット変更がない状態から開始。既存UI・アニメーション・保存形式を維持する。Project.json、権限設定、バックアップ形式、録音処理は変更しない。

## 調査と採用判断

| 対象 | 観察された処理 | 改善方針と安全条件 | 比較方法 |
|---|---|---|---|
| PerformanceLog | 1計測ごとに最大500件をJSON化・SQLiteへ保存 | 即時表示は維持し、診断ログだけ1秒の固定窓でまとめる。失敗時のrevisionを保持し、背景移行・リセットは同期確定。業務保存のキューと原子性は維持 | 本番logger/queue、隔離backend、500件保持中の100件burstを21回 |
| LibraryView | 各レコードに対し既存セクションを線形検索 | 辞書を併用する候補を検証したが、最終比較で1000件の差は0.066ms、100件は悪化。効果が小さいため元の実装へ戻した | 旧メソッドを基準から抽出し0/1/100/1000件、昇順・降順・タイトル順の完全一致 |
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

Phase 2の最終DEBUGビルド成功（`2026-10-13T22-36-57-9a962f43.log`）。SelfCheck failedはなく、Performance caches成功。Home→Library、ファイル/プロジェクト切替、既存2記録の日付セクション、既存WeeklySync、FAB/composerの表示を確認。本文や原本の編集・削除は行っていない。

## Phase 3

- LocalStoreの3つのSQLを既存lock内で再利用。毎回reset/clear_bindingsし、読取のblobは従来通りDataへコピー。失敗後のstatementも再使用可能。deinitでfinalize/closeする。
- ProjectSearchIndexのstatement再利用は初回構築1000資料で263.541→261.635ms、100資料で16.614→16.780msと実効差を確認できず、不採用に戻した。actorの不要なhandleをdeinitで閉じる処理だけ保持。
- LocalStoreのopen初期化が失敗した場合にはhandleを閉じ、次のprepareで再試行できる。保存先・SQLite schema・WAL・同期レベル・JSON codec・transaction境界は変更しない。test用に保存先を注入できるが、通常のデフォルトパスは同じ。
- 同期確定・削除・録音・復元の順序とエラー伝播は維持。業務documentのsaveをdebounce/非同期化/skipする変更は採用していない。
- 実SQLiteへの旧schema/旧JSON bytes読取、triggerでの失敗注入による複数document rollback、draft保持、同じキーの順序、失敗後retry、再open、削除、50並行書込を検証。RecordStoreFailureChecksでproduction queueの失敗・順序も確認する。
- 関連チェックの再実行入口: `MEMORA_CHECK_TMPDIR=<一時領域> TMPDIR=<一時領域> python3 tools/checks/run-optimization-checks.py`。外部通信・実ユーザーデータへの保存は行わない。

初回batch比較（1000document各2KiB、21回、並行buildによるばらつきあり）: 21.123/33.008/35.316ms → 8.649/9.136/11.449ms。これは多数documentのSQL再使用を検証するfixtureであり、Memoraの「会議配列を1つのdocumentへ保存」の時間を表してはいない。

## 保留する改善候補

| 優先度 | 候補 | 保留理由・効果・リスク |
|---|---|---|
| 高 | 実機Releaseで起動/スクロール/メモリ/描画trace | xctraceで実機がoffline。処理単位の改善を実操作の効果へ結び付ける必要がある |
| 中 | 大きい同期確定batchのJSON encodeをworkerへ移す | メインアクター待ちを減らせる可能性。Sendable snapshot、削除/復元/録音の順序、エラーと終了時耐久性を別途検証する必要がある |
| 中 | 資料本文の質問をまたぐキャッシュ | I/O削減の可能性はあるが、backup復元・同名ファイル差し替え・permission変更時の鮮度証明が必要。mtime/sizeだけを信用する実装は採用しない |
| 中 | 日別recap/全文検索結果の永続的な派生cache | 時刻/日付/健康/カレンダー/人名/チーム/編集をすべて無効化する複雑さに対して未計測。実際のHome全体traceを先に取る |
| 低 | 全ストレージ移行、モデル全面分割 | 今回のscope外。互換性/耐久性のリスクに対して根拠がない |

高頻度の録音レベル、タイマー、再生位置は既存のleaf Viewで読まれている。bottom bar、safeArea、Liquid Glass、zoom/matchedTransition、NavigationStackの実装は保持し、広範囲のview階層やbindingの変更は行わない。

追加点検: ProjectContextのsource/task ID確認が各資料に対する線形検索だった。既存IdentifiableIndexをsource/taskにも再利用し、配列のdidSetで必ずinvalidateする。保存するのは位置だけで、本文/許可は現在の配列から読む。編集・許可取消・削除・並べ替え・重複IDの最初の項目を維持するSourceLookupChecksが成功。1000件を各1回検索するwarm比較は0.579→0.159ms。100件は0.012→0.016msで差が小さい。初回の索引構築はこのwarm比較に含まない。

## 最終比較

固定日時・固定ID・同一文字列で再測定。並行build中の初回値は参考値に留め、下表は各21回の中央値/p95/最大（ms）。OSのI/Oや別プロセスによるばらつきは残り、統計的な信頼区間は未算出。短縮率は中央値から計算した処理単位の値。

| 処理 | 変更前 中央値/p95/最大 | 最終 中央値/p95/最大 | 中央値短縮 |
|---|---:|---:|---:|
| AI順位 100件 | 1.339 / 1.583 / 1.586 | 0.929 / 1.145 / 1.163 | 30.6% |
| AI順位 1000件 | 39.690 / 43.483 / 44.211 | 5.844 / 5.984 / 5.990 | 85.3% |
| 100ログburst（500件保持） | 70.932 / 72.001 / 73.932 | 1.341 / 1.736 / 1.869 | 98.1% |
| burst 21回の保存数 | 2100 | 21 | 99.0%減 |
| 索引反復 100資料 | 3.479 / 3.529 / 3.666 | 0.745 / 0.781 / 0.796 | 78.6% |
| 索引反復 1000資料 | 30.945 / 31.944 / 31.988 | 3.493 / 4.545 / 4.859 | 88.7% |
| 索引再構築 100資料 | 16.614 / 22.950 / 33.607 | 16.773 / 23.232 / 39.904 | -1.0%（短縮なし） |
| 索引再構築 1000資料 | 263.541 / 270.762 / 286.963 | 267.091 / 277.851 / 298.004 | -1.3%（短縮なし） |
| SQLite batch 100×2KiB | 1.301 / 3.175 / 4.383 | 1.053 / 3.112 / 4.102 | 19.1% |
| SQLite batch 1000×2KiB | 9.223 / 11.626 / 16.168 | 8.994 / 10.571 / 14.948 | 2.5% |
| 所有者判定 1000件 | 2.376 / 2.410 / 2.439 | 0.377 / 0.386 / 0.387 | 84.1% |
| ID全件検索 1000件・warm | 0.579 / 0.833 / 0.851 | 0.159 / 0.185 / 0.186 | 72.5% |

初回索引構築は改善していない。JSON/grams/FTS構築を伴うコールドパスをwarm hitの短縮率で評価しない。ファイル日付分類の候補は100件0.306→0.345ms、1000件2.554→2.488msで、最終コードでは不採用。LocalStoreのbatchは多数のdocumentを保存するfixtureであり、会議/タスクの配列全体を1documentにJSON化する時間の証明ではない。

| 要求された実操作の項目 | 状況 |
|---|---|
| 起動〜操作可能、Home表示完了 | 未測定。PerformanceLogの既存起動値は同じappVersionの過去試行が混在するため比較値に使わない |
| ファイル一覧100/1000・画面検索 | 処理単位の順位/分類を測定。実描画時間と画面検索全体のbefore/afterは未測定 |
| プロジェクトAI | 索引同期＋検索は上表。ファイル実読取/JSON復号/モデル応答を含む全質問時間は未測定 |
| 画像decode | 共有・寸法・取消・削除・memory warningを検証。decode時間のbefore/afterは未測定 |
| 会議/タスク保存 | SQLite batchとqueue failureを検証。JSON encode込みの実機保存時間は未測定 |
| CPU/メモリ | Debugシミュレータの単発RSS 417744KiB（約408MiB）、CPU 0.0%を観測。baselineなし。アイドル中央値、操作時・peak、実機Releaseは未測定 |
| 描画フレーム/不要再描画 | 未測定。Time Profiler attachは`Cannot find process for provided pid`でtrace取得できず。実機もoffline |

## 最終品質確認

- 関連CLIチェック20 suiteが成功（SourceLookupChecksを含む）。DEBUG起動ログにSelfCheck failedなし、Performance caches成功。memory warningによる解放も実際のNotification経路で検証。
- Homeの変更前/変更後スクリーンショットを目視比較し、時計表示以外の配置・文字・色・glassが一致。pixel単位の自動比較/動画/フレーム計測はしていない。
- iPhone 18 Pro MaxでHome、日付切替、日別サマリー開閉、Files検索（日本語はsetValueで入力）/消去/キャンセル、元の2記録、録音詳細、project一覧/詳細、record/project/globalのcomposer、Ask AI、FAB popoverのcapture actionsと閉じる動作、Settings/DEBUG画面、Light/DarkのHome/Settingsを確認。表示設定・選択日は元に戻した。
- 元の録音2件、既存タスク、WeeklySync、ゴミ箱3件を保持。ユーザーデータの追加/変更/削除/復元は行っていない。DEBUGの私有画像fixtureとCLIの一時データだけを作成し、fixtureは終了時に削除。
- 録音開始/停止/バックグラウンド復旧、実機audio割込、実カレンダーの遅い応答、ネットワーク障害、有料AI/CloudKit/外部サービス、widget実表示、実バックアップ復元は未実施。既存のaudio/保存/backup自己チェックとhostのfailure fixtureを実操作の証明とはしない。
- Project.json、Info.plist、entitlements、保存/backup codec、tab/FAB/Glass/navigation/animationの実装は変更なし。各PhaseのDebugビルド成功。最終Releaseビルドも成功（`2026-10-13T23-52-50-f1702250.log`、Release/-O/whole-module optimizationをログで確認）。既存AppIntents metadata警告1件のみ。
- 最終のProjectEvidenceInput比較はUTF-8バイトと時刻のbitPatternを確認する。Swift Stringの通常の同値判定ではUnicodeの表現差を見落とすため、同じ見た目でも保存JSONが変わった資料を必ず再同期する。Caféの合成/分解表現とsigned zeroの回帰チェック成功。上の索引値はこの検証を含む最終実装で再測定した。
- memory warningはcacheを解放し、表示中のrowがawaitしているdecodeを取り消さない。generationを進めて古いdecodeのcache再投入だけを抑止する。読み込み途中で警告が来てもplaceholderのままになることを避け、取消済みのrowへの反映拒否は維持する。
- 画像のcache/in-flight keyにはファイルURLも含める。旧photo名がfull./workspace.で始まっても別の媒体と要求を混同しない。DEBUG私有fixtureでは本物の計測ログへ画像タイミングを追加しない。

## 変更ファイル

App: HomeActivityLinks、HomeView、JournalSummaryView、JournalTimelineBuilder、LifeLogRow、LocalStore、MediaImageCache、MeetingRanking、MemoraModel、MemoraModel+AI、MemoraModel+ProjectContext、MemoraModel+ProjectSources、MemoraModel+Tasks、PerformanceCacheChecks、PerformanceLog、ProjectContextBuilder、ProjectEvidenceInput、ProjectSearchIndex、RecordStore、SelfChecks、SummaryPreviewCache、TaskOwnership（各.swift）。LibraryViewは候補の検証後に元のコードへ戻し、基準との差分はない。

tools/checks: CollectionPerformanceChecks、JournalPerformanceChecks、LocalStoreChecks、PerformanceLogChecks、ProjectIndexBenchmark、ProjectSearchIndexChecks、SourceLookupChecks（各.swift）、run-performance-checks.py、run-local-store-checks.py、run-optimization-checks.py、run-project-index-benchmark.py。ドキュメントはこのファイルだけ。

## Git

- Phase 1: `5e7e5d8` — 診断ログ、AI順位、画像/preview cacheと回帰fixture。
- Phase 2: `06f7570` — 確定済み索引入力の再利用、所有者判定、イベントの照合、古いcalendar応答の排除。
- Phase 3: `57f5e0f` — SQLite statement、source/task ID lookup、rollback/並行書込、効果の薄い候補の撤回。
- 最終検証のコミットIDは完了報告に記載する。作業終了時に全変更をコミットする。GitHubへの追加pushはこの最適化依頼には含めない。
## 共通添付抽出（2026-10-14）

会話用のファイル読取・PDF・OCRはdetached taskで実行し、本文構築から
同期I/Oを除外した。プロジェクトの既存抽出を再利用し、会話添付はサムネイル
なし。最大50MiB・テキスト512KiB・PDF20ページ・画像2,000pxの上限を共有。
端末内の短縮再試行では再解析しない。実機の時間／メモリは未計測。
## スコープ付きエージェント（2026-10-14）

projectは6往復・8操作、recordは3往復・3操作。本文と追加抜粋を有界にし、
MCPの不要なschemaを送らない。単体読取ではプロジェクト全体の索引を再登録
しない。処理状態は変更時だけ代入し、100msの本文更新で同じ状態を繰り返して
親画面を再描画させない。検索窓は文字数を制限し、質問に一致する部分を残す。
これらは実機の性能計測値や金額の強制上限ではない。

## 2026-10-16 Motion / Loading / Streaming / Native Harness

基準main `5dc9774`。保存済み情報の0.75秒text revealと段階的Appearを呼出し側から除去。操作用MemoraMotion、native Glass/FAB/Heroを保持。詳細と検証表は [MOTION_LOADING_HARNESS.md](MOTION_LOADING_HARNESS.md)、外部設計比較は [NATIVE_AGENT_HARNESS.md](NATIVE_AGENT_HARNESS.md)。Project.json、保存codec、録音処理、権限設定は変更なし。

streamは最初の文字を即時、その後最短100msの既存公開制御を保持。新しい増分parserは確定段落を再解析せず、未完tailだけ更新。live/settledで同じblock rendererを利用する。構造化UIは従来どおり全受信・検証後だけ表示する。本文開始後のstatus shimmerは静止textへ替える。

Host Swift -O、架空18,130 bytes/92更新、11回、ContinuousClock。毎更新の全文parse候補の合計中央値/p95は22.125/34.541ms、増分は2.546/3.036ms。解析入力848,098/20,993 bytes。これは同じMarkdown parserを使う方式比較で、旧live Textとのbefore/afterや実機frame改善率ではない。`tools/checks/MarkdownStreamingBenchmark.swift`がfixture。起動・Home・tab・detail・hitches・main thread占有・peak memory・network初回回答・skeleton頻度の実機Release値は未測定。

Loadingの閾値は180ms/2秒/5秒を共通化。高速ローカル一覧は即時表示。日付とcalendar設定へ予定を束ね、古い日付のイベントをrecap/summaryへ渡さない。本文の非同期読取はsource/参照/retryとtokenで取消・古い応答を拒否。refreshは既存本文を保持する。

Agentの新しい診断eventは要求/操作の事実と終了所要時間だけで、本文・引数・キーを記録しない。request/byte/時間の上限は有限のローカルguardであり、ドル金額やtoken課金の強制上限ではない。


### SSE受信境界の追加検証（2026-10-16）

`CloudByteFramingBenchmark.swift`をホストのswiftc `-O`で実行。架空の74,752 bytes / 1,024 SSE events、warmup 1回を除く11回で、最終版CloudSSEEventDecoderのフレーミングはp50 **0.66ms**、p95 **0.71ms**。バイト単位の入力、wire容量検査、UTF-8とSSEの区切り解析を含む。URLSession、モデル、JSON tool解析、Markdown、SwiftUI、スクロール、端末メモリは含まない。実iPhone Releaseの数値やUI改善率として扱わない。

中間実験の非同期byte wrapperは同規模fixtureでp50 11.13ms（wrapperなし1.23ms）となり採用しなかった。最終版は受信loopの内側で同期的に容量を確認する。実装や測定範囲が異なるため、旧アプリからの高速化率を算出しない。従来の`.lines`によるSSEの空行消失は性能比較以前の正確性の問題として修正した。100msの公開間隔は維持し、virtual clockテストで最初のtextと最終flushも確認した。

### Markdown更新の処理単位比較（2026-10-16追加）

基準`1cb1d8d`の増分parserと最終コードを同じbinaryで交互に21回測定。行数確認のための2回目の全文splitを除去した。架空コードblock23,903 bytes/174更新の合計中央値は25.453→16.761ms、長い1段落29,400 bytes/123更新は8.965→6.076ms。短い段落caseのp95は改善しておらず、実機frame/UI改善率は未測定。文法/編集範囲とnative UIを維持する。条件・全case・再実行方法・最新Time Profiler接続失敗は[MARKDOWN_UPDATE_PERFORMANCE.md](MARKDOWN_UPDATE_PERFORMANCE.md)、生の集計は[MARKDOWN_UPDATE_BENCHMARK.json](MARKDOWN_UPDATE_BENCHMARK.json)を参照。
