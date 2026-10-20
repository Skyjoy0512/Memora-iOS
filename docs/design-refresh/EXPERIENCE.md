# 全体のUI/UX磨き込み — 2026-10-20

設定の整理に続き、主要な日常動線へ共通の読み方・操作感を適用した。
ネイティブUI設計スキルを使い、[一覧](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、
[検索](https://developer.apple.com/design/human-interface-guidelines/searching)、
[シート](https://developer.apple.com/design/human-interface-guidelines/sheets)の方針に沿って設計。
親画面の文脈、内容と操作の区別、大きな文字での折り返しを優先する。

## 変更内容

| 対象 | 改善 |
|---|---|
| ジャーナル | 画面名と年月を表示。「今日に戻る」を実装。タスク・最近のプロジェクト・空状態をフラットにし、タイムライン見出しを統一 |
| 日次サマリー | タップして開けることが分かるラベルと開示記号。文章や出典・背景選択は維持 |
| ライブラリ | 画面名を表示。空状態の見出しと操作名の重複を解消。プロジェクトをまたぐ一覧であることを説明 |
| 検索 | 未入力時の説明と結果なしの復旧操作を統一。プロジェクトの元一覧が背後に残る状態と、ソースのみ一致した際の0件表示を修正 |
| ワークスペース | チャット／ファイル／ソースの3タブを維持。空状態を共通化し、大きな文字ではスクロールして操作へ到達可能に |
| タスク | フラットな一覧、空状態から実際に追加、元記録のタイトルを表示、チェックと元記録ボタンの44pt操作枠 |
| 人物・資料 | 共通の空状態と実際の追加／Ask AIへの入口。行の補助文を共通Typographyで折り返す |
| 記録詳細 | 無題のフォールバック、長いタイトル、日時・時間・記録元を一つの折り返す文章として表示 |
| 作成メニュー | 円形装飾を廃止し、統一したSF Symbolと用途説明。内容実寸に合わせた高さとスクロール |

## 共通部品

`MemoraEmptyState` は空・未入力・検索結果なし・絞り込み結果なしに使う。
見出し、説明、任意の**実際に機能する**操作を持ち、背景カードを重ねない。
`ProjectWorkspaceEmptyState` は削除し、新旧2系統を維持しない。

`MemoraSectionHeading` は文脈や件数を添える見出し。大きい文字では縦配置へ変わる。
`MemoraActionLabel` はボタンの中に置く説明付き行で、余白を含めて操作領域とする。
`MemoraMenuButtonStyle` は押下時だけ中立色を使い、常時の装飾タイルは作らない。

最大文字サイズでは年月／日付復帰、タスク見出し／一覧へのリンクを縦に配置する。
「今日」は同じ位置に残り、今日を表示中は無効化する。選択日を変えたときに
ヘッダーの高さや操作位置が急に変わらないようにした。

ジャーナル画面の追加操作は選択日をフォームの初期日付へ渡す。
これは日次サマリーで既に使われていた初期化方法と同じ。
UIからの追加時だけ一時的に日付を指定し、シートを閉じると解除するため、
外部の新規メモ操作は従来どおり現在日時で開く。保存処理や既存の記録は変えない。

## 変えないもの

録音・読み込み・オンライン会議の実行処理、保存先の取得、保存形式、API、権限・料金承認、
日本語IME、ドラフト、会話履歴は変更していない。資料の「Ask AIを開く」は既存のシステム
ナビゲーションを利用し、新規チャットを作らず下書きを保持する。
下部UISegmentedControlと＋のGlass／popover／zoom、主要スクロールの制御は維持。
Ask AIの空画面に挨拶や装飾は追加していない。

今回の対象は上表の画面と共通部品。全設定・全編集シート・実サービスの全状態を
新たに検証済みとするものではない。

## 検証と比較画像

変更前はコミット `c4760de` の実アプリを専用テスト端末で撮影。
変更後も同じ端末・OSで撮影し、画像の生成・合成は行わない。
Bitrigプレビューとは別のiPhone 18 Pro Max／iOS 27.0を使用し、
テスト端末のアプリだけを初期化する。実データのあるプレビューは初期化しない。

### ビルド・ホスト検査

`bitrig preview -platform iOS` は成功し、ユーザーのプレビューへ反映済み。
最終ビルドログは `2026-10-20T16-29-23-ea513ff4.log`。iOS 26ターゲット／27.1 SDK。
既存のMapKit・OAuth非推奨APIとApp Intentsメタデータの警告11件は今回の範囲外。

以下はすべて通過した。

- `bash tools/checks/run-design-refresh-checks.sh`：新規の画面構造契約5件を含む、デザイン・Markdown・Loading・Agent・プロジェクト送信の検査。
- `bash tools/checks/run-ask-ai-plugin-checks.sh`：IME・メンション・registry dispatch・権限・料金・OAuth・ナビゲーションの検査。
- `python3 tools/checks/run-optimization-checks.py`：SQLite保存／再読込・検索所属・ドラフト・Journal・ファイル参照の回帰検査。
- `git diff --check`。

`bitrig test` は終了コード78。このProject.jsonにXcodeテストターゲットはないため、
XCTest成功とは扱わない。ホストのモック検査と、実アプリを動かすE2Eを区別する。

### iOS操作検証

新規 `tests/experience-polish.e2e.ts` の9/9件が最終ビルドで通過。
空状態からの実際の追加、タスク完了の再起動後の保持、検索語の解除、元一覧の非表示、
ソースのみ一致した場合の件数、Ask AIへのドラフト保持、日付の復帰、作成メニューから
オンライン会議の準備画面までの到達、選択日の記録保存と再起動、外部新規メモの今日への保存を確認した。
外部APIやAIモデルを呼び出さない決定的な操作テストで、課金や録音は開始していない。

同じ最終ビルドで関連する既存E2E 9/9件も通過。グローバル／プロジェクトの@選択、
フォーカス・複数選択・削除・＋経由の候補表示、長文Markdownの編集とSQLite再読込、
会話の日本語文章、ワークスペースの3タブ、週カレンダー、インライン追加、
記録の日付編集、プロジェクトの絞り込みを対象とした。

システムの文字サイズを **Accessibility XXXL** に変更した別実行でも4/4件が通過。
@候補の位置と44ptの閉じる操作、検索語の消去とキーボード維持、日付の復帰、
作成メニューのスクロールと実際の準備画面への遷移を確認した。
大きな文字を縮小して1画面へ押し込まず、縦配置やスクロールで到達させる。
テスト後は専用端末の文字サイズをLargeに戻している。

Dark表示の補完2/2件も最終ビルドで通過。タスク・人物・資料、および
ワークスペースのファイル／ソースを撮影した。テスト終了後の外観はLightへ戻した。
各実行のID・ケース・対象範囲は [RESULTS.json](experience/RESULTS.json) に保存している。

途中の回帰では、起動遷移中の43.91ptを操作領域の最終寸法として検査してしまうケースが1件あった。
アプリの44pt枠は縮めず、テスト側を遷移後に44pt以上になるまで確認する方式へ修正。
44pt未満を許容する誤差や、固定の待ち時間は追加していない。最終の9件ではすべて通過した。

### 比較画像

| 画面 | Before | After |
|---|---|---|
| ジャーナル Light | [画像](experience/before/journal-light.png) | [画像](experience/after/journal-light.png) |
| ジャーナル Dark | [画像](experience/before/journal-dark.png) | [画像](experience/after/journal-dark.png) |
| ライブラリ Light | [画像](experience/before/library-light.png) | [画像](experience/after/library-light.png) |
| ライブラリ Dark | [画像](experience/before/library-dark.png) | [画像](experience/after/library-dark.png) |
| 作成メニュー Light | [画像](experience/before/create-light.png) | [画像](experience/after/create-light.png) |
| 作成メニュー Dark | [画像](experience/before/create-dark.png) | [画像](experience/after/create-dark.png) |
| タスク Light | [画像](experience/before/tasks-light.png) | [画像](experience/after/tasks-light.png) |
| 人物 Light | [画像](experience/before/people-light.png) | [画像](experience/after/people-light.png) |
| 資料 Light | [画像](experience/before/documents-light.png) | [画像](experience/after/documents-light.png) |

追加のAfter： [タスク Dark](experience/after/tasks-dark.png)／[人物 Dark](experience/after/people-dark.png)／
[資料 Dark](experience/after/documents-dark.png)／[タスク操作](experience/after/tasks-active.png)／
[検索の復旧](experience/after/project-search.png)／[ソースの検索件数](experience/after/source-search.png)／
[選択日への保存](experience/after/selected-day-saved.png)。

関連する最終ビルドのAfter：
[ワークスペースのファイル](experience/after/workspace-files.png)／
[ワークスペースのソース](experience/after/workspace-sources.png)／
[ファイル Dark](experience/after/workspace-files-dark.png)／[ソース Dark](experience/after/workspace-sources-dark.png)／
[長文要約 Light](experience/after/summary-long-light.png)／[Dark](experience/after/summary-long-dark.png)／
[会話 Light](experience/after/conversation-light.png)／[Dark](experience/after/conversation-dark.png)。
文章の画像はテスト用と明示された架空の入力であり、生成サービスの成功例ではない。

Accessibility XXXL：
[ジャーナル](experience/after/journal-accessibility.png)／
[作成メニュー（スクロール後）](experience/after/create-accessibility.png)／
[会議準備](experience/after/online-accessibility.png)／
[@候補](experience/after/mentions-accessibility.png)／
[検索](experience/after/search-accessibility.png)。

### 残る確認境界

全42件のE2E一括実行ではなく、変更範囲に対応したケースの選択実行。
iOS 26の実行環境、実機VoiceOverでの聴取、手動の日本語IME変換、
認証済みの外部連携、実マイク録音と実サービスでの文字起こし・課金は今回未検証。
これらをコンパイルやモック検査から検証済みとは扱わない。
初回刷新の[全体比較](REVIEW.md)、前段の[設定レビュー](SETTINGS.md)も別途参照。
