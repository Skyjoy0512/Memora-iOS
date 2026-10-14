# メインナビゲーション再設計（2026-10-12）

## 画面構成と再利用

現行構成はジャーナル（内部IDはHome）｜ライブラリ｜Ask AIの3タブ＋右端の独立FAB。RootTab／RootNavigationとAGENTS.mdの順序を基準とする。作成済みのプロジェクト一覧・カード・ホーム導線・タスク画面を引き継いだ。

2026-10-14: ウィジェット／App Intentsも既存の各NavigationStackへ遷移する。
今日のタスクは既存の「今日取り組む」フィルターを適用。Ask AIリンクの
フォーカス要求は共有AIComposerBarで一度だけ消費し、通常のタブ操作は
変更しない。新規会話、処理中の会話の維持、独立FAB、UISegmentedControlの
Morphingは保持。詳細と検証境界は[NEXT_GENERATION_AI.md](NEXT_GENERATION_AI.md)。

ホーム → 既存HomeViewのカレンダー、日別タイムライン、背景、日別サマリーとHero遷移を維持。カレンダー・日別サマリーの後に、今日取り組むタスク・期限の近いタスク・すべて見る・最近使用したプロジェクトへの導線を追加。

ライブラリのプロジェクトセグメント → 作成済みProjectsViewを子コンテンツとして再利用。名前検索、最近使用したプロジェクト、全プロジェクト、作成、名前変更、削除、共有。チームから共有されたプロジェクトも所有者名付きで表示し、既存SharedProjectViewを閲覧専用で開く。

ライブラリ → 既存LibraryViewにファイル／プロジェクトのGlassSegmentedPickerを追加。ファイル選択では所属にかかわらずmodel.meetingsを一覧・検索する。並べ替え、表示切替、選択、移動、削除、共有、既存録音詳細のzoom遷移を維持。資料・人物・設定・外部レコーダー・ワークスペースは既存サイドバーから開く。

Ask AI → SearchView、AIQuestionView、QuickAIComposer、既存アイコンと会話UIを維持。

既存のMemoraSpace、MemoraModel+Spaces、SpaceDetailView、TasksView、TaskRow、TaskEditView、AddTaskView、RenameSpaceSheet、FileCreationSheet、SharedOwnerBadge、CaptureMenuPopover、memoraCardを再利用。永続レコード・SQLiteスキーマ・音声保存形式・AI処理・RecordAccessPolicyは変更していない。プロジェクトの未完了タスク数は既存の派生インデックス方式に合わせ、値が変わったときだけ更新する。

## 新しいコンポーネント

- ProjectsView: 前回の一覧・検索・編集導線を保持するライブラリの子コンテンツ。NavigationStack・タイトル・検索ツールバーは親LibraryViewが所有。
- LibrarySection: ファイル／プロジェクトの選択。UserDefaultsで保持し、初回・不明な旧値はfilesへ復元。
- ProjectCard: 既存カードスタイルで名前、記録数、未完了タスク数を表示。
- HomeActivityLinks: タスクと最近使用したプロジェクトへの導線。
- LibraryDestinationView: 共通の既存画面への遷移。ライブラリ固有の録音zoom遷移はLibraryViewに残す。
- RootNavigation: タブごとの経路、録音先、AIスコープの判定。
- MemoraModel+Navigation: プロジェクト、保存した録音、タスク通知の経路接続。

## タスクとナビゲーション

TasksViewの内部NavigationStackだけを外し、HomeViewのNavigationStack内のLibraryRoute.tasksから開く。作成、編集、完了、相手待ち、担当者、期限、親子関係、リマインダー、チームボード、元の録音への遷移は既存の実装を利用する。ホームの候補はisOwnTask（TaskOwnership）、workDate、dueDateを利用し、プロジェクトに属さない自分のタスクも含める。期限の近いタスクには期限切れと今後7日以内を含める。

タスク通知は既存のtaskReminderTappedからopenTaskへ接続する。同じホームタブで検索中でも、直接遷移時は検索状態を解除してタスク画面を開く。memora://task/<UUID>も同じ画面を開く。個別録音の既存Deep Linkはライブラリで開く。

独立プロジェクトタブとprojectsPathを整理し、ライブラリ内の単一NavigationStack・libraryPathに統合。homePathは独立。作成直後・ホームの最近使用したプロジェクトからはライブラリのプロジェクトセグメントへ移動する。各タブの経路は切り替え後も保持する。RootTab.libraryのrawValueは旧filesを維持する。selectedTab自体は以前から永続化されていない。旧識別子の変換も自動チェックする。

最近使用したプロジェクトは詳細を実際に開いた順に最大8件のIDを保持する。これはUserDefaultsに保存するナビゲーション設定で、プロジェクト本体は既存SQLiteのまま。削除されたIDは表示から除外される。

## FABとAIスコープ

ProminentTabBarのUISegmentedControl、右端の独立FAB、サイズ・余白・glassボタン・popover・matchedTransitionSource・zoom遷移は維持。タブラベルの描画幅を実際のセグメント幅に合わせ、大きいDynamic Typeではアイコンのみとする。VoiceOverのタブ名は残す。スクロール制御の判定ロジックは変更しない。

visibleProjectIDは選択中のタブの経路を読み、最後の経路が存在する編集可能なプロジェクト詳細のときだけIDを返す。共有プロジェクトや一覧では保存先を指定しない。CaptureMenuPopoverは既存のままで録音・取り込み・オンライン会議へIDを渡す。保存後はそのプロジェクトの経路へ戻り、プロジェクト削除時は既存の未分類フォールバックを使う。

通常のAsk AI画面はglobal、プロジェクト詳細はspace、録音・文字起こしはfile。Ask AI内の値ベースの経路を通らない録音詳細もfileになる。詳細の開始元タブを記録して、タブ変更時の前画面のコンテキスト混入を防ぎ、閉じるときもそのタブの登録だけを除去する。既存のAIエンジン・アクセス制御を引き続き通す。

## 自動チェック

- RootNavigationChecks: 成功。3タブの順序、旧ID、独立した経路、録音先、共有プロジェクト除外、全体／プロジェクト／録音のAIスコープ、Ask AI内の録音詳細、前タブのコンテキスト混入防止。
- RecordPrivacyChecks: 成功。未許可の拒否、一度だけの同意、機密分類、保存の往復。
- StandaloneRecordPrivacyChecks: 成功。旧形式、明示許可、親レコード継承、孤立した関連、機密区分の下限、位置情報の除外。
- SelfChecks: Main navigationを追加し、Tab bar iconsを更新。実行結果の確認は下記のシミュレーター記録を参照。
- git diff --check: 成功。
- bitrig build -destination selected: 3タブ実装で成功。既存警告5件（AutoLocationLoggerの3件、RecordStoreの1件、App Intentsメタデータの1件）。

## シミュレーター検証

iPhone 18 Pro Maxの実際の表示・操作で確認した項目:

- 3タブの表示とホーム／ライブラリ間の切り替え。右端の独立FABとフローティングcomposerの配置。
- ライブラリのファイル／プロジェクトの切り替え。ファイル一覧に既存の2録音が残り、既存WeeklySyncプロジェクトも表示される。
- ホームから既存TasksViewへの遷移、未所属の自分のタスクの新規作成、タイトル編集・保存、今日取り組む設定、ホームへの反映。
- ライブラリから検証用プロジェクトを作成して詳細を開く。
- プロジェクト詳細のFABメニューに保存先が表示され、通常録音を開始・終了・保存できる。保存後も同じプロジェクトで録音が1件として表示される。
- プロジェクト内の録音を開き、戻るとプロジェクト詳細へ戻る。
- プロジェクト詳細の入力欄がプロジェクト名、録音詳細の入力欄が録音名になる。プロジェクトのAI質問シートも検索範囲にプロジェクト名を表示する。
- プロジェクト一覧へ戻ると入力欄はグローバルになり、FABに前の保存先が残らない。一覧から別の録音を保存しても前のプロジェクトの件数は1件のまま。
- ホームに最近使用したプロジェクトがコンパクトに表示され、そこからライブラリのプロジェクト詳細へ直接移動できる。
- ホームとライブラリを往復しても、ライブラリのプロジェクトセグメントが選択されたまま。

実際の文字起こしは「この端末では利用できません」、プロジェクトのAI回答はAPIキー未設定として拒否された。スコープ表示・保存・遷移の検証と、モデルによる回答成功は区別する。タブ選択の状態と遷移は確認したが、アニメーションの時間変化を動画等で測定してはいない。

追加で実操作を確認した項目:

- Ask AIを含む3タブの切り替え。プロジェクトセグメントはアプリ再起動後も復元された。
- タスク完了と元の録音・文字起こしへの遷移。
- プロジェクト検索、名前変更、削除。プロジェクト削除後も録音はファイル一覧に残る。
- ファイルの検索、カード／一覧表示、並べ替え、状態フィルター、複数選択と一括削除。選択中は既存の操作バーが表示され、タブとcomposerが隠れる。
- FABから音声取り込みのファイル選択画面、オンライン会議の既存案内画面を開く。実ファイルの取り込みとオンライン録音は実施していない。
- サイドバーから資料、人物、設定へ移動。
- 大きいDynamic Type（accessibility_extra_large）でプロジェクト名・件数・タブとFABの表示を確認。Reduce Motion有効時のタブ切り替えも確認。
- カレンダーの日付変更、既存の日別サマリーの表示と終了。Hero遷移の時間変化を測定した検証ではない。
- 設定の自己チェック画面でMain navigationとTab bar iconsの成功表示を確認。

検証用プロジェクトとタスクは削除し、検証用録音2件はゴミ箱へ移した。元からあった有効な録音2件・タスク・WeeklySyncプロジェクトは残っている。検証用録音は復元可能。

iPhone 17eへの端末変更後、操作APIが「simulator device is not booted.」を返した。iPhone 18 Pro Maxへ戻してビルド・操作を再開できたが、小型iPhoneでの実表示は未確認。

未確認: 音声ファイルの実取り込み、実際のオンライン会議録音、共有データの実受信、ダークモード、VoiceOverによる操作、通知配信とタップ、Deep Linkの外部起動、小型iPhone。これらの既存実装と導線は保持したが、操作済みとはしない。

## 実機・外部サービスでの確認

後続検証ではシミュレーターで実際のタスク通知配信・通知からの編集画面遷移、およびSafariからの録音Deep Link起動を確認した。最新の結果と未確認範囲は [REMAINING_VALIDATION.md](REMAINING_VALIDATION.md) を参照。上記の未確認一覧は初回実装時点の記録。

実機のバックグラウンド録音、ロック中の録音、Omi等の外部レコーダー、タスク通知の配信とタップ、カレンダーと位置情報、CloudKitの実メンバー間共有、外部モデルによる回答品質は別途確認が必要。未接続サービスを今回の変更で接続したことにはしない。

## 変更ファイル

- `AGENTS.md`
- `App/FileCreationSheet.swift`
- `App/FileSidebarView.swift`
- `App/HomeActivityLinks.swift`
- `App/HomeView.swift`
- `App/LibraryDestinationView.swift`
- `App/LibrarySection.swift`
- `App/LibraryRoute.swift`
- `App/LibraryView.swift`
- `App/MeetingDetailView.swift`
- `App/MemoraModel+Capture.swift`
- `App/MemoraModel+Import.swift`
- `App/MemoraModel+Navigation.swift`
- `App/MemoraModel+Samples.swift`
- `App/MemoraModel+Spaces.swift`
- `App/MemoraModel.swift`
- `App/ProjectCard.swift`
- `App/ProjectsView.swift`
- `App/ProminentTabBar.swift`
- `App/RootNavigation.swift`
- `App/RootTab.swift`
- `App/RootTabView.swift`
- `App/SelfChecks.swift`
- `App/SpaceDetailView.swift`
- `App/TasksView.swift`
- `App/TranscriptView.swift`
- `DESIGN.md`
- `Shared/MemoraIcon+Lucide.swift`
- `Shared/MemoraIcon.swift`
- `docs/MAIN_NAVIGATION.md`
- `tools/checks/RootNavigationChecks.swift`
