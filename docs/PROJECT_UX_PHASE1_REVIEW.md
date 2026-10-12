# Memora Project UX — Phase 1 / 承認前レビュー

2026-10-12。レビュー時のステータス：**提案のみ・本番UI未変更**。その後、オーナーの「実装して」で承認済み。実装・検証結果は [実装報告](PROJECT_UX_PHASE1_IMPLEMENTATION.md) を参照。

対象は Skyjoy0512/Memora-iOS の現在のBitrig作業ツリー。調査時のローカルHEADは `a2af105`、GitHub main は `1635207`。ローカルの位置修正を巻き戻さず、最新の「ライブラリ見出しの下にある切り替え」を基準にした。GitHubへの新しいpushは行っていない。

AGENTS.mdのHome/Library順の記述には、現行RootTabとオーナーの最新指定との不一致がある。設計は実際の「ライブラリ | ジャーナル | Ask AI」を優先する。AGENTS.md自体は今回変更していない。

## 比較資料

[比較ビューア](design/project-phase1/index.html)には、一覧0・1・10・100件、詳細の通常・空・大量データ、Light/Dark、資料までスクロールした状態の10組を収録。

- [一覧10件 Before / After](design/project-phase1/list-10.png)
- [詳細通常 Before / After](design/project-phase1/detail-normal.png)
- [一覧0件](design/project-phase1/list-0.png)、[一覧1件](design/project-phase1/list-1.png)、[一覧100件](design/project-phase1/list-100.png)
- [詳細空状態](design/project-phase1/detail-empty.png)、[詳細大量データ](design/project-phase1/detail-many.png)
- [一覧Dark](design/project-phase1/list-dark.png)、[詳細Dark](design/project-phase1/detail-dark.png)
- [関連資料の導線](design/project-phase1/detail-documents.png)

画像は架空データによる**模式図**。Beforeも実データのスクリーンショットではない。現在のiPhone 18 Pro Maxで一覧1件・記録0件の詳細を実際に観察し、構造をコードと照合した。0・10・100件をアプリへ投入していない。SwiftUI Previewの登録やアプリ内プロトタイプ画面は追加していない。

Glassは位置だけを描いており、反射・屈折・Morphing・Safe Areaを証明する画像ではない。承認後のネイティブ実装を別途検証する。

## 1. 現状のUXレビュー

|重要度|現状とコードの根拠|原因・ユーザーへの影響|改善案|
|---|---|---|---|
|高|[ProjectCard](../App/ProjectCard.swift#L13)は44ptのアイコン枠、上下18pt、件数の別行。[ProjectsView](../App/ProjectsView.swift#L32)はカード間12pt|通常サイズでも1件が約114pt。プロジェクト名に比べて背景・アイコンの面積が大きく、件数が増えると比較しにくい|背景のない2行のリスト。名前17pt、補助13pt、アイコン18〜20pt。最小行高72pt、長文・Dynamic Typeでは伸長|
|高|[ProjectsView](../App/ProjectsView.swift#L22)は4件以上でrecent最大3件を表示し、そのIDを全件から除外しない|同じプロジェクトが横スクロールと全件に現れる。100件では探す前に重複分をスクロールする|既定は単一一覧。「最近使用を先に」を選んだ場合だけ、recentと残りを排他的なセクションにする|
|中|[ProjectsView](../App/ProjectsView.swift#L12)はspacesの現在の配列順で検索する。一覧のソートUIはない|作成順と利用順を区別できない。「最新更新順」を付けても現行モデルにはその日付がない|表示専用の名前順／最新記録順と任意の最近使用優先。検索は既存のtoolbarSearchを維持|
|中|[LibraryView](../App/LibraryView.swift#L127)の作成と[ProjectsView](../App/ProjectsView.swift#L44)の空状態ボタンが同じsheetを開く|空の一覧に同じ作成操作が二つある|右上の「作成」を唯一の入口にする。空状態は場所を短く案内する|
|高|[SpaceDetailView](../App/SpaceDetailView.swift#L155)の本文と[同ビューのnavigationTitle](../App/SpaceDetailView.swift#L96)が同じ名前を表示。52ptアイコンもある|名前・説明・件数・操作がヘッダーに集中し、実際の記録やタスクが下へ押される|名前はシステムのLarge Title一つ。スクロール後は同じ標準タイトルがinlineになる。本文は件数の1行のみ|
|高|[SpaceDetailView](../App/SpaceDetailView.swift#L21)の順序がoverview→AI質問→全録音→タスク|タスクは全録音の後。録音が100件あれば、次の行動を確認するまで長いスクロールが必要|次にやること最大3件→最近の記録3件→関連資料。全件は同じ画面内で展開|
|高|[SpaceDetailView](../App/SpaceDetailView.swift#L182)の録音・インポートと[CaptureMenuPopover](../App/CaptureMenuPopover.swift#L54)が同じcapture/import処理を呼ぶ|大きな重複操作が情報の主役になっている|本文の大きなcaptureボタンを整理し、既存の右端FABを主入口にする。録音中・準備中・保存中の挙動を先に照合する|
|高|[SpaceDetailView](../App/SpaceDetailView.swift#L28)のAIボタンは定型質問を付ける。[AIQuestionView](../App/AIQuestionView.swift#L339)は表示時に実行。[QuickAIComposer](../App/QuickAIComposer.swift#L65)は入力した質問を同じsheetへ渡す|回答先とscopeは同じだが、ワンタップの定型質問と自由入力は異なる。単純削除で便利な操作が失われる|下部入力欄を主入口にし、定型質問はメニューの「未決事項を質問」に移す。自動実行・回答・履歴保存は維持|
|高|[ProjectFilePickerSheet](../App/ProjectFilePickerSheet.swift#L50)は選択した既存記録を**移動**する|「追加」から複製・複数所属を期待すると、元プロジェクトから消えたことに驚く|入口名を「既存記録を移動」に統一。既存sheetの移動先・元から非表示になる説明を維持|
|中|[SpaceDetailView](../App/SpaceDetailView.swift#L47)とL79は記録0件・タスク0件でも別々の空セクションを表示|新規プロジェクトが空状態の説明で埋まる|全内容が空なら一つの案内。記録あり・タスクなしならタスクなしを一行だけ。資料なしはセクションを省略|
|中|[MemoraDocument](../App/MemoraDocument.swift#L14)にspaceIDはあるが、SpaceDetailViewに資料の表示はない|資料が同じプロジェクトに属していてもサイドメニューへ戻る必要がある|関連資料の読み取り一覧と既存.documentルートを任意追加。資料作成・所属変更・RAGは追加しない|

ユーザーが以前指摘した文字の拡大を繰り返さない。本文17ptは現在のbody/headline相当のまま。小さくすることで一覧性を稼ぐ案ではない。名前をLarge Title一つにする変更は今回の承認対象であり、まだ実装していない。

## 2. 確認したデータとナビゲーションの境界

|対象|現行の事実|提案で守る境界|
|---|---|---|
|プロジェクト|MemoraSpaceはid/name/symbolのみ。日時・進捗・AIサマリーはない|最終更新や進捗の数値を推測しない。新しい永続モデルを作らない|
|最新記録日|[MemoraModel](../App/MemoraModel.swift#L723)のaggregate.latestDateは最新Meeting.createdAt|「最新記録」と表示。「最終更新」と呼ばない。編集日時や資料更新との合成は別設計|
|関連タスク|[SpaceDetailView](../App/SpaceDetailView.swift#L236)はプロジェクト録音のID集合とtask.meetingIDを照合し、未完了だけを抽出|直接task.spaceIDを仮定しない。共有担当・自分以外の関連タスクも現在と同じ集合。TasksViewの「自分のタスク」フィルターへ置き換えない|
|録音先|[MemoraModel+Spaces](../App/MemoraModel+Spaces.swift#L4)は現在経路の最後が.spaceの場合のみ有効なspaceIDを返す。RootTabViewからFABへ渡す|詳細トップだけが保存先。プロジェクト一覧・録音詳細・共有詳細に直前IDを残さない|
|移動・削除|[ProjectFiling](../App/ProjectFiling.swift#L14)はMeeting.spaceIDを変更。[deleteSpace](../App/MemoraModel+Spaces.swift#L68)は録音と資料を未分類へ戻す|コピー扱いにしない。削除確認とatomicな保存処理をそのまま使う|
|AI|RootNavigation.scopeで.space、.file、.globalを決定。QuickAIComposerの非globalはAIQuestionView。成功時にsaveAIExchangeへ保存|下部入力欄・質問sheet・履歴・RecordAccessPolicyを変更しない。scopeをUI都合で広げない|
|資料|MemoraDocument.spaceID/updatedAtとLibraryRoute.document(id)、DocumentDetailViewが存在|既存の文書・スライドだけを表示。PDF・メール・写真を扱えるという表示を追加しない|
|資料のAI|AIQuestionViewの対象はallowedMeetingsとscopedTasks。資料本文は送っていない|資料を表示してもAI全文検索はできると案内しない。「AI質問は録音・タスクが対象」を必要な場所で示す|
|資料閲覧時のscope|既存RootNavigationでは.documentは.global、visibleProjectIDはnil|.document経路を使う場合も現行仕様を保持。資料スコープ新設や親プロジェクトへの暗黙継承は別フェーズ|
|共有|共有IDはString、SharedProjectView/SharedRecordViewのsnapshotを閲覧。編集可能なMemoraSpaceとは別|一覧で所有者・閲覧のみを明示し、名前変更・削除・captureを付けない。架空の.space UUIDを作らない|

プロジェクトから直接タスクを新規作成する所属関係、プロジェクト本体の更新日時、資料RAG、共有snapshotの編集は今回のUI変更で解決しない。

AIの経路も区別する。プロジェクトの質問はAIQuestionViewからmodel.answerへ進み、グローバルの入力はsendAIChatへ進む。画面を簡略化するためにプロジェクト質問をAsk AIタブの会話・エージェントへ送る変更はしない。

## 3. 推奨ワイヤーフレームと状態設計

### 一覧：単一の2行リストを推奨

```text
メニュー                             検索  作成
ライブラリ
             [ ファイル | プロジェクト ] ←現在の位置を維持
プロジェクト · 10件                   並べ替え
小アイコン  プロジェクト名                  …
            記録12件 · 最新記録10/12
──────────────────────────────────────────
小アイコン  別のプロジェクト名              …
            記録0件
チームから共有（存在する場合）
            名前 / 所有者 / 閲覧のみ
        ［既存AI入力欄］
［ライブラリ | ジャーナル | Ask AI］ ［＋］
```

- 既定は単一一覧、作成入口は右上に一つ。ellipsisの44pt領域は行のNavigationLinkと別にして、誤って開かないようにする。名前変更・共有・削除は現在のsheet/dialog/処理を再利用。長押しの同じ操作も残す。
- 名前を最優先し、件数・日付は補助情報へ。タスク件数は詳細で確認できるため、一覧では基本表示しない。共有所有者と読み取り権限は省略しない。
- 初期順は名前順を推奨。最新記録順も選択可能。空の記録日は末尾、同値は名前で安定化。View内で一度だけsort/filterし、行ごとに再集計しない。
- 「最近使用を先に」は任意。known recent最大3件と、IDで除外した残りを表示する。検索中は単一結果一覧。現行の直近8件の利用設定は完全な最終使用日時ではないため、100件すべての最終利用順を保証する表現は避ける。

|状態|表示・操作|
|---|---|
|0件|小さな空状態と右上作成への案内。既存emptyの大きな作成ボタンを重複させない。共有だけ存在する場合は共有一覧を表示し、個人一覧の空カードを重ねない|
|1件|同じ72pt以上の行を1件。大きい特別カード・recent重複は不要|
|10件|複数行が一画面で比較できる。検索・並べ替え・任意のrecent優先|
|100件|遅延描画のリスト、行単位の安定したID、一覧全体で一度だけ検索・ソート。ページング・新検索エンジンは不要|
|長い名前・大きい文字|名前は2行まで、VoiceOverは全文。行高を伸ばす。補助情報が入らなければ日付を折り返す。固定高で切らない|

比較候補：A「背景なし＋細い区切り線」を推奨。B「区切り線なし＋余白のみ」はさらに静かだが、100件では境界が分かりにくい。C「小さな薄灰色の行」は今のカードから移りやすいが、カードの面積を減らす目的に対し効果が弱い。図はA。

### 詳細：行動と記録を主役にする

```text
戻る                                      …
プロジェクト名 ←標準Large Title一つ／スクロールでinlineへ
記録12件 · 未完了タスク5件

次にやること                      すべて見る（5）
○ タスク名              期限（必要なときのみ）
○ タスク名
○ タスク名

最近の記録                       すべて見る（12）
記録名
日時 · 記録種別 · 必要な状態表示
（最初は3件）

関連資料（存在する場合・任意の承認対象）
文書名／種類／更新日                すべて見る

［既存の「このプロジェクトに質問」入力欄］
［ライブラリ | ジャーナル | Ask AI］ ［＋］
```

- 名前の重複と大きなアイコンをなくし、標準navigationTitleでLarge→inlineの動きをシステムに任せる。scroll offsetでバーの表示を制御する実装は追加しない。
- 「次にやること」は既存TaskRowを再利用。集合・順序・完了処理を維持し、先頭最大3件を表示。今回はAI優先度や新しい所有権判定を導入しない。完了して次の行が現れる挙動とVoiceOverフォーカスを検証する。
- 「すべて見る」は同じList内の表示件数を展開し、「折りたたむ」で戻す。別のTasksViewへ送って、無所属や他プロジェクトのタスクを混ぜない。全記録も同じ画面で展開する。
- 最近の記録はcreatedAtの新しい順で3件。全件表示では現在のsortとcard/list設定を維持し、メニュー名を「全件の表示」として適用範囲を明示する。設定済みの表示モードを黙って上書きしない。
- 個別録音は従来のLibraryRoute.meeting、タスク編集は従来のTaskEditView sheet。長押し・移動スワイプも維持する。録音失敗・処理中などの意味のある状態表示を密度のために消さない。
- 本文の大きな録音・インポートを除き、既存FABを主入口にする。ただし録音中のSpaceDetailボタンは「録音画面を開く」となるため、FABと既存の録音状態表示から同じ画面へ到達できることを検証してから除去する。到達性が不足する場合は、小さな「録音画面を開く」導線を録音中だけ残す。CaptureMenuPopoverの実装変更は原則行わない。
- 定型AIボタンは「未決事項を質問」としてellipsisメニューへ。元の質問・.space・自動実行・回答sheet・履歴保存を残す。共有も同じメニューへまとめ、すべての機能を消さずにトップの操作数を減らす。
- 「既存記録を移動」はFABの新規capture/importと別。内容がある場合はellipsisの一箇所、全内容が空の場合は本文の短いリンク一箇所を推奨。現在のpickerと移動後の結果通知を維持する。

|状態|表示・操作|
|---|---|
|全内容が空|名前・件数と一つの開始案内。右下＋で録音/取り込み、短いリンクで既存記録を移動。空のタスク・資料セクションを並べない|
|タスク0・記録あり|「未完了タスクはありません」を一行。最近の記録を次に表示|
|記録0・資料あり|録音なしの短い案内と関連資料。架空の記録・タスクを生成しない|
|記録100・タスク24|初期の先頭3件ずつ。全件をインライン展開すると全件へアクセスできる。通常の状態へ折りたたみ可能|
|共有|既存SharedProjectViewを使い、閲覧のみと所有者を保持。今回の編集可能な詳細と同じタスク・操作を仮定しない|

### 関連資料の任意追加

model.documentsをspaceIDで一度だけfilterし、updatedAt順の最大3件を表示。LibraryRoute.document(id)を使えば既存の閲覧・編集・エクスポートへ接続でき、DB移行は不要。全件は同じListで展開し、DocumentsViewのグローバル一覧は変更しない。資料の新規所属変更・資料作成ボタンは追加しない。

資料を開くと現行routeではAIがglobalになり、FABの保存先はnilになる点を承認時に確認する。これをプロジェクトscopeへ拡張する案は今回に含めない。資料が見えることと資料本文をAI検索できることを混同させないため、図では対象範囲の短い注記を設けた。

## 4. Before / Afterと設計寸法

|比較軸|Before|推奨After|
|---|---|---|
|一覧1件|約114ptカード＋12pt間隔|最小72ptの2行。17pt本文は維持、補助は13pt相当|
|10・100件|recentの重複＋カード連続|通常は単一リスト、必要なら排他的なrecentセクション|
|一覧スクロール量|概算126pt×件数＋recent領域|概算73pt×件数。行部分の高さは約4割減を見込む|
|詳細の最初の注目点|名前が二つ、大きな操作・AI、全記録|名前が一つ、実際の未完了タスク、最近の記録|
|タスクまでの距離|全記録件数に依存|ヘッダーのすぐ後。記録100件でも初期の位置が同じ|
|追加操作|本文の録音/取込、FAB、ファイル追加の複数箇所|新規captureはFAB、既存の所属変更は一箇所|
|AI|定型質問ボタン＋自由入力|自由入力を主役に、定型質問はメニューに保持|
|資料|サイドメニュー経由|任意追加で詳細から直接既存の資料を閲覧|

約4割は標準サイズの設計寸法からの見込み。SwiftUI上の実測値、100件の描画性能、タップ数のユーザーテスト結果ではない。長い名前やアクセシビリティサイズでは同じ比率にならない。

提案値：横マージン16pt（プロジェクト内容だけ）、セクション間24/32pt、行内12/16pt、最小行高72pt、操作対象44pt以上。名前17pt semibold／本文17pt regular／補助13pt regular／セクション15pt semibold。標準Dynamic Type対応。名前だけ標準Large Title。既存のGlass段は位置・サイズ・効果を変更しない。

MonochromeはMemoraPaletteを再利用。白/0B背景、F5/2020カード等の既存tokenは維持。背景のない補助情報はtextSecondary、カード上は既存のcardTextSecondary（Lightは707070）を使い、コントラストを落とさない。資料や録音の意味のある警告色・ユーザー画像は保持。

設計参考：[Apple HIG Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[Writing](https://developer.apple.com/design/human-interface-guidelines/writing)、[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)。テキストの一覧性、簡潔な言葉、補助操作の意味が明確なメニューを優先する。

## 5. 承認後の実装計画

|段階|変更候補|再利用・リスク|
|---|---|---|
|1. 共通寸法|プロジェクト専用の小さなlayout定数。必要な場合のみProjectLayout.swift|MemoraPaletteは変更しない。アプリ全体のフォント・余白を巻き込まない|
|2. 一覧|ProjectsView.swift、ProjectListRow.swift、必要ならLibraryView.swiftのプロジェクト用ソート操作|ProjectCardのactions、RenameSpaceSheet、共有処理、既存検索、LibraryRoute.spaceを移す。全件が接続されるまでProjectCardを削除しない|
|3. 詳細|SpaceDetailView.swift、ProjectRecordRow.swift|既存Listとvalue-based NavigationLink、TaskRow、TaskEditView、ProjectFilePickerSheet、BulkSpacePickerSheet、既存menu/sheetを維持|
|4. 資料（任意）|SpaceDetailView.swift、小さなProjectDocumentRow.swiftを必要なら追加|既存DocumentDetailViewと.documentへ接続。DocumentRowの全画面共通スタイルを変更しない|
|5. 空・大量・外観|上記view内の小さなsection/empty helper|ProjectHeaderなど7種類を最初から作らない。実際に複数箇所で使うものだけ共通化|
|6. 回帰|既存RootNavigationChecks/Privacyチェック、viewの抽出/重複防止チェックを必要時のみ追加|ビルドと実操作を分け、各段階でコミット・結果報告|

UI専用の並べ替えenum/設定は必要最小限。最近使用を変える場合も現在のrecentIDsを参照するだけで、新たなプロジェクトDBモデルは作らない。一覧・詳細でtask集合を共通化する場合もSpacesの既存算出を使い、ownership・保存・完了ロジックを変更しない。

変更しない領域：LocalStore/RecordStore・StorageKey・MemoraSpace/MemoraTask/MemoraDocumentの保存形式、MemoraModel+Spacesの移動/削除/保存、録音/STT、API/AIエンジン、課金/認証/権限、Deep Link、共有backend、RootTabの順序。

Glass保護対象：RootTabView、ProminentTabBar、MemoraGlass、GlassSegmentedPicker/Control、QuickAIComposer、CaptureMenuPopover、BottomBarScrollBehavior。原則これらのファイルは変更しない。UISegmentedControl、glassEffect/ID/Container、FABのmatchedTransitionSource＋popover＋zoom、safeAreaInset/bottomContentClearanceを保つ。AI・録音先の不整合が見つかった場合も、UI修正に混ぜず原因と最小修正を別途報告する。

既存の`.space/.meeting/.document/.sharedProject`やsheetを使う。新しいNavigationStack・Task/Record用の全件routeは追加しない。承認案の「すべて見る」は画面内展開であって、既存の戻る/Deep Link仕様変更ではない。

## 6. 回帰検証と承認時のリスク

|リスク|必須検証|
|---|---|
|UI移設で機能が見えなくなる|作成・検索・名前変更・削除・共有・ソート・全件のcard/list設定・定型AI質問が引き続き到達できる|
|録音入口の一本化|新規録音・録音中画面・準備/保存/復元中の無効化、音声取り込み、online meeting、正しいspaceID保存、詳細を離れた後のnil、既存移動の結果|
|タスクの切り詰め|0/1/3/4/24件、完了で次が見える、全件展開/折りたたみ、他人の関連タスクも保持、元の録音・編集・期限・通知導線|
|recent重複|0/1/3/10/100プロジェクト、検索中、削除済みID、recentと残りのIDが重複しない、Homeのrecent導線・選択復元|
|AI機能の差|自由入力と元の定型質問、成功/未接続/拒否、.space/.file/.global、他プロジェクト混入、RecordPrivacy/RecordAccessPolicy、回答履歴|
|資料のscope差|spaceIDで正確な資料のみ、旧データnil、資料編集・更新日・export、資料から戻る、.document中の既存globalとFAB nilを明示的に確認|
|Glass/スクロール|3タブ順序、右端FAB、popoverの開閉・zoom、pickerの選択Morphing、下部入力欄、キーボード、ユーザー操作時のみタブが隠れる、戻ると復帰|
|アクセシビリティ|Light/Dark、Increase Contrast、Reduce Transparency、Reduce Motion、通常/最大Dynamic Type、長い日本語・タップ領域、VoiceOverの行名・完了・menu・展開状態・フォーカス|
|共有の権限|SharedProject/Recordの閲覧のみと所有者、編集・captureを誤って許可しない|

自動チェックは集合・順序・旧データ・scopeの境界を検証する。ビルド成功を全UIの保証にしない。シミュレーターではview操作・外観・通知・遷移を確認し、実機ではマイク/背景録音/ロック/外部レコーダーを確認する。実CloudKit共有・外部AI・実際のonline meetingは接続された環境で別途確認する。

現在の17/17eシミュレーターは以前の検証で起動観測APIが失敗している。小型画面・最大文字の検証は承認後の必須条件であり、実施済みとはしない。紙面は390pt相当の模式図で、最小幅の実機確認ではない。

今回実施したのはコードレビュー、GitHub HEAD照合、現行一覧/空詳細の観察、PNG生成・画像の目視確認。提案UIのビルド/操作/Glass検証は未実施。本番Swiftファイルを変更していない。

資料作成後の既存アプリは `bitrig build -destination selected` で成功（2026-10-12、App Intentsメタデータの既存警告1件）。比較ビューアのJavaScript構文・ID・10画像の参照、PNGのデコード、レビューのローカルリンクも検査した。HTMLはブラウザー上での実操作未確認。既存アプリのビルド結果を提案UIの機能保証とは扱わない。

## 7. オーナー確認

推奨は **Aの一覧＋詳細再配置（①②）**。関連資料（③）は、資料閲覧時のglobal scopeとAI検索対象の制約を許容できる場合のみ含める。

1. 一覧：背景なしの2行、作成一箇所、任意のrecent優先・重複除去・並べ替え。
2. 詳細：単一Large Title、タスク先頭3件、最近記録3件、同じ画面内の全件展開、captureはFAB、定型AI/共有はmenu、既存記録は「移動」と明記。
3. 任意：関連資料の閲覧導線（RAGなし／資料中のscopeは既存global）。

「①②を承認」「①②③を承認」、または直したい箇所を指定してください。**明示的な承認があるまで、本番UIの実装変更を開始しない。**
