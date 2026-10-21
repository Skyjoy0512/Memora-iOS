# UI/UX 全体点検（2026-10-21）

## 確認の意味

ソース走査と実画面の確認は別です。この記録は「全画面を実機で目視済み」という意味ではありません。

- Swiftソース 912 件を走査し、Viewを含む 326 ファイルを抽出。
- ファイル名から画面・シート・エディター候補 180 件を一覧化。補助View・診断用UIも含みます。
- 共通ルールの静的検査：旧グループ背景、未統一の標準List、白文字と可変tintの組み合わせ。現在の検出は0件。
- 静的検査はレイアウト、色のコントラスト、全ての操作が正しいことを証明するものではありません。

再実行：

```sh
node tools/checks/ui-surface-audit.mjs
node tools/checks/ui-surface-audit.mjs --inventory
```

## この点検で揃えたもの

- 履歴、メール下書き、人物／保存先の選択、カレンダー、外部レコーダー、共有一覧、診断画面に共通のフラットな `MemoraList` を適用。
- `MemoraForm` は同じListの行ルールを利用し、ネイティブの入力・選択・保存処理を維持。
- プラン、アカウント、初回案内、要約生成、ロック解除、録音保存で、主要アクションの文字色・形状を共通化。
- ネイティブツールバーはシステムの余白を含めて44pt、独自ガラスはラベル自体を44ptとし、二重の余白を避ける。
- テンプレート一覧、録音方法、週報カードの装飾タイルを通常のアウトラインアイコンに整理。
- 資料、共有記録、文字起こし、ソース本文、ジャーナル、振り返りに読み幅680pt・通常20ptの外側余白を適用。
- 写真編集、PDF、地図などのネイティブキャンバス、状態の色、公式ロゴはその役割を維持。
- サイドメニューの設定・アカウント等は、画面全体のアニメーション完了ではなく、ドロワー自身の移動完了後に開く。別のアニメーションに待たされ、設定が開かないケースを修正。
- 未接続のメール認証画面で「パスワードをお忘れですか？」を押した場合も、無反応ではなく既存の未接続案内を表示。

## 操作検証の範囲

専用のE2Eシミュレーターを利用。テスト用アプリの再インストールはBitrigのプレビューとは別で、普段の記録を削除しません。

- `bitrig preview -platform iOS`：最終アプリ変更のビルド成功、プレビュー更新済み。既存の非推奨API等の警告11件は残っています。
- 初回の選択21ケース：17件通過、4件失敗。設定が開かない経路3件と、背後のライブラリにもある「プロジェクト」のテスト指定の曖昧さ1件を確認。前者はアプリを修正し、後者はドロワー側の項目を明示。
- 最終アプリ版での再確認8ケース：8件全通過（リトライなし）。初回失敗4件、主要4画面からの設定遷移を追加した1件、アカウント／プラン1件、ツール／下書きの既存2件を含みます。
- 初回と再確認を合わせて異なる22ケースを扱っています。最終版で22件を一括再実行した、という意味ではありません。
- ライト／ダークでの入力欄拡縮、設定一覧・プロフィール入口、アカウント／プラン、長文本文、チャット回答の表示を確認。
- タスクの追加・再起動後の保持、長文要約のブロック編集・SQLite再読込一致、下書きの画面間保持、履歴／検索、プロジェクトの絞り込み、ソース追加、ファイル選択導線、表示検証ギャラリー6画面を対象に含めました。
- Bitrigプレビューでは、Ask AIから設定が開くことと、設定・プラン等の見た目を別途確認。E2Eの表示検証ギャラリーは実データ／実サービスの検証とは区別しています。

再確認コマンド：

```sh
npx e2e run tests/screen-polish.e2e.ts tests/settings-polish.e2e.ts tests/chat-surface.e2e.ts tests/design-refresh.e2e.ts tests/minimal-polish.e2e.ts --grep 'Settings opens after|account and plan|topic hierarchy|capture composer and sidebar|long Markdown|conversation typography|minimal polish' --output .e2e/regression/all-screen-polish-recheck --workers 1 --retries 0
```

初回成果物：`.e2e/regression/all-screen-polish/`、再確認成果物：`.e2e/regression/all-screen-polish-recheck/`（ローカル検証用、Git管理外）。

## スキル編集・ツール検索（追加点検）

- 必須項目と文字数上限の案内、手順のプレースホルダー、キーボードの「完了」、未保存変更の破棄確認を追加。
- ツールの3分類は同じツールバー検索を使う。空結果の案内はキーボードより上に置き、大きい装飾アイコンを使わない。
- `SkillEditingPolishChecks`：必須項目・文字数超過・入力を切り詰めないこと・和文区切り・重複除去・変更判定・ID／スコープ保持・複数語／全角検索のチェックが通過。
- 最初の4ケース実行では、保存／再起動後の保持／チャット指定、ツールメニューと詳細、3分類の検索と詳細から戻る操作の3件が通過。編集キャンセルの1件は、確認ポップオーバーに「編集を続ける」が表示されず失敗。二者択一の標準アラートへ修正。
- 修正後の最終版で4ケースすべて通過（リトライなし）。編集の継続・破棄に加え、無変更なら確認なしで閉じることも確認。成果物は `.e2e/regression/skill-editing-polish-verified/`（Git管理外）。
- 最終 `bitrig preview -platform iOS` 成功、プレビュー更新済み。ログ `2026-10-21T18-06-28-66121e2b.log`。既存の警告11件は残る。
- ライト／ダークの入力画面、検索一覧、キーボード表示中の空結果、公式アイコン付きコネクタの画像を確認。専用E2Eアプリのみを再インストールし、Bitrigプレビューの普段の記録は変更していない。
- 長文のネイティブ自動入力は2回タイムアウト。401文字と400文字上限の案内の表示は画像で確認したが、長文入力の一連のUIテストが通過したとは扱わない。上限判定は上記のロジックチェックで別途確認。

再実行：

```sh
npx e2e run tests/skill-polish.e2e.ts tests/answer-actions.e2e.ts tests/minimal-polish.e2e.ts --grep 'skill polish:|reusable skills:|[Tt]ools menus' --output .e2e/regression/skill-editing-polish-verified --workers 1 --retries 0
```

## 検証していない条件

- 文字サイズ変更・VoiceOverなどの追加検証は依頼どおり保留。既存の対応コードは削除していません。
- OAuth実認証、実課金、CloudKit共有、外部レコーダー実機、未接続バックエンドを使う完了状態は未検証。
- 通話は現在の機能フラグを維持。画面の共通色は整えていますが、通話機能は有効化していません。
- 実録音を始める、実データを外部に送る、購入する操作はUI点検のために行いません。
- 表示検証ギャラリーは架空データです。実サービスの動作確認には数えません。

## ソース上の画面候補一覧

以下の全候補が静的走査の対象です。実操作の全数確認ではありません。

- [ActiveCallView.swift](../App/ActiveCallView.swift) — 専用ビュー
- [ActivityView.swift](../App/ActivityView.swift) — 専用ビュー
- [AddPeopleSheet.swift](../App/AddPeopleSheet.swift) — NavigationStack / MemoraList
- [AddTaskView.swift](../App/AddTaskView.swift) — NavigationStack / MemoraForm
- [AgentActivityView.swift](../App/AgentActivityView.swift) — 専用ビュー
- [AgentTaskDraftEditor.swift](../App/AgentTaskDraftEditor.swift) — NavigationStack / MemoraForm
- [AgentTaskDraftExampleView.swift](../App/AgentTaskDraftExampleView.swift) — ScrollView
- [AgentTaskOperationCheckView.swift](../App/AgentTaskOperationCheckView.swift) — ScrollView
- [AIAnswerActionsExampleView.swift](../App/AIAnswerActionsExampleView.swift) — MemoraForm
- [AIAnswerTextSelectionView.swift](../App/AIAnswerTextSelectionView.swift) — NavigationStack / ScrollView
- [AIComposerInteractionExampleView.swift](../App/AIComposerInteractionExampleView.swift) — MemoraForm
- [AICreditsView.swift](../App/AICreditsView.swift) — MemoraForm
- [AIHistoryDetailView.swift](../App/AIHistoryDetailView.swift) — ScrollView
- [AIHistoryView.swift](../App/AIHistoryView.swift) — NavigationStack / MemoraList
- [AIInterfaceStructuredExampleView.swift](../App/AIInterfaceStructuredExampleView.swift) — ScrollView
- [AIMarkdownBaselineExampleView.swift](../App/AIMarkdownBaselineExampleView.swift) — ScrollView
- [AIMarkdownPolishExampleView.swift](../App/AIMarkdownPolishExampleView.swift) — ScrollView
- [AIMemoryEditingExampleView.swift](../App/AIMemoryEditingExampleView.swift) — MemoraForm
- [AIMemoryEditor.swift](../App/AIMemoryEditor.swift) — NavigationStack / MemoraForm
- [AIMemoryView.swift](../App/AIMemoryView.swift) — MemoraForm
- [AIMessageView.swift](../App/AIMessageView.swift) — NavigationStack
- [AIPluginIconView.swift](../App/AIPluginIconView.swift) — 専用ビュー
- [AIPluginSetupView.swift](../App/AIPluginSetupView.swift) — MemoraForm
- [AIQuestionView.swift](../App/AIQuestionView.swift) — NavigationStack / ScrollView
- [AISettingsView.swift](../App/AISettingsView.swift) — MemoraForm
- [AIUserMessageView.swift](../App/AIUserMessageView.swift) — 専用ビュー
- [AllMeetingsView.swift](../App/AllMeetingsView.swift) — List
- [APIKeySheet.swift](../App/APIKeySheet.swift) — NavigationStack / MemoraForm
- [ArtifactSourceDetailView.swift](../App/ArtifactSourceDetailView.swift) — NavigationStack
- [ArtifactSourcesExampleView.swift](../App/ArtifactSourcesExampleView.swift) — MemoraList
- [ArtifactSourcesView.swift](../App/ArtifactSourcesView.swift) — 専用ビュー
- [AskAIExperienceExampleView.swift](../App/AskAIExperienceExampleView.swift) — ScrollView
- [AuthView.swift](../App/AuthView.swift) — NavigationStack / ScrollView
- [BulkSpacePickerSheet.swift](../App/BulkSpacePickerSheet.swift) — NavigationStack / MemoraList
- [CalendarEventSheet.swift](../App/CalendarEventSheet.swift) — NavigationStack / MemoraList
- [CalendarSelectionView.swift](../App/CalendarSelectionView.swift) — MemoraForm
- [CallExplanationView.swift](../App/CallExplanationView.swift) — ScrollView
- [CallIntroView.swift](../App/CallIntroView.swift) — 専用ビュー
- [CallKeypadSheet.swift](../App/CallKeypadSheet.swift) — 専用ビュー
- [CallVerifiedView.swift](../App/CallVerifiedView.swift) — 専用ビュー
- [CaptureSessionView.swift](../App/CaptureSessionView.swift) — ScrollView
- [CloudShareSheet.swift](../App/CloudShareSheet.swift) — 専用ビュー
- [CompanyTemplateDetailView.swift](../App/CompanyTemplateDetailView.swift) — MemoraForm・ネイティブメディア
- [CompanyTemplatesView.swift](../App/CompanyTemplatesView.swift) — MemoraForm
- [ConnectContactsView.swift](../App/ConnectContactsView.swift) — 専用ビュー
- [ContentView.swift](../App/ContentView.swift) — NavigationStack
- [DesignSystemReviewView.swift](../App/DesignSystemReviewView.swift) — MemoraList / ScrollView
- [DialerView.swift](../App/DialerView.swift) — NavigationStack / List
- [DocumentDetailView.swift](../App/DocumentDetailView.swift) — ScrollView・ネイティブメディア
- [DocumentEditSheet.swift](../App/DocumentEditSheet.swift) — NavigationStack / MemoraForm
- [DocumentsView.swift](../App/DocumentsView.swift) — List / ScrollView
- [EmailAuthView.swift](../App/EmailAuthView.swift) — MemoraForm
- [ExcludedPlacesView.swift](../App/ExcludedPlacesView.swift) — MemoraForm
- [ExternalRecorderSettingsView.swift](../App/ExternalRecorderSettingsView.swift) — MemoraForm
- [FileCreationSheet.swift](../App/FileCreationSheet.swift) — NavigationStack / MemoraForm
- [FileSidebarView.swift](../App/FileSidebarView.swift) — ScrollView
- [GlossaryMailSuggestionsView.swift](../App/GlossaryMailSuggestionsView.swift) — NavigationStack / MemoraForm
- [GlossaryView.swift](../App/GlossaryView.swift) — MemoraForm
- [GmailSettingsView.swift](../App/GmailSettingsView.swift) — MemoraForm
- [HealthReviewStatusView.swift](../App/HealthReviewStatusView.swift) — 専用ビュー
- [HomeView.swift](../App/HomeView.swift) — NavigationStack / ScrollView
- [InlineCitationExampleView.swift](../App/InlineCitationExampleView.swift) — 専用ビュー
- [InlineMarkdownEditor.swift](../App/InlineMarkdownEditor.swift) — 専用ビュー
- [IntegrationDetailView.swift](../App/IntegrationDetailView.swift) — ScrollView
- [IntegrationsView.swift](../App/IntegrationsView.swift) — List
- [InteractionFeedbackView.swift](../App/InteractionFeedbackView.swift) — 専用ビュー
- [IOSIntegrationSettingsView.swift](../App/IOSIntegrationSettingsView.swift) — MemoraForm
- [JournalBackdropView.swift](../App/JournalBackdropView.swift) — 専用ビュー
- [JournalMapSheet.swift](../App/JournalMapSheet.swift) — NavigationStack・ネイティブメディア
- [JournalMovementSheet.swift](../App/JournalMovementSheet.swift) — NavigationStack / MemoraList
- [JournalReviewView.swift](../App/JournalReviewView.swift) — NavigationStack / ScrollView
- [JournalSummaryView.swift](../App/JournalSummaryView.swift) — NavigationStack / ScrollView
- [LibraryDestinationView.swift](../App/LibraryDestinationView.swift) — 専用ビュー
- [LibraryView.swift](../App/LibraryView.swift) — NavigationStack / List
- [LicenseActivationView.swift](../App/LicenseActivationView.swift) — MemoraForm
- [LifeLogCreationSheet.swift](../App/LifeLogCreationSheet.swift) — NavigationStack / MemoraForm・ネイティブメディア
- [LifeLogEditSheet.swift](../App/LifeLogEditSheet.swift) — NavigationStack / MemoraForm
- [LifeLogEntryDetailView.swift](../App/LifeLogEntryDetailView.swift) — NavigationStack / ScrollView
- [LLMModelPickerView.swift](../App/LLMModelPickerView.swift) — MemoraForm
- [LLMProviderPickerView.swift](../App/LLMProviderPickerView.swift) — MemoraForm
- [LockScreenView.swift](../App/LockScreenView.swift) — 専用ビュー
- [MailDraftSheet.swift](../App/MailDraftSheet.swift) — NavigationStack / MemoraForm
- [MailDraftsView.swift](../App/MailDraftsView.swift) — MemoraList
- [MarkdownBlockView.swift](../App/MarkdownBlockView.swift) — 専用ビュー
- [MarkdownDocumentView.swift](../App/MarkdownDocumentView.swift) — 専用ビュー
- [MCPServerEditor.swift](../App/MCPServerEditor.swift) — NavigationStack / MemoraForm
- [MCPServersView.swift](../App/MCPServersView.swift) — MemoraForm
- [MCPSettingsView.swift](../App/MCPSettingsView.swift) — MemoraForm
- [MeetingDetailView.swift](../App/MeetingDetailView.swift) — ScrollView・ネイティブメディア
- [MotionLoadingGalleryView.swift](../App/MotionLoadingGalleryView.swift) — ScrollView
- [NativeAIInterfaceExampleView.swift](../App/NativeAIInterfaceExampleView.swift) — ScrollView
- [NativeAIInterfaceView.swift](../App/NativeAIInterfaceView.swift) — 専用ビュー
- [NotionSettingsView.swift](../App/NotionSettingsView.swift) — MemoraForm
- [OccupationSelectionView.swift](../App/OccupationSelectionView.swift) — MemoraForm
- [OmiDeviceDetailView.swift](../App/OmiDeviceDetailView.swift) — MemoraList
- [OmiPairingView.swift](../App/OmiPairingView.swift) — NavigationStack / MemoraList
- [OnboardingView.swift](../App/OnboardingView.swift) — TabView / NavigationStack
- [OnlineMeetingCaptureView.swift](../App/OnlineMeetingCaptureView.swift) — MemoraList
- [PaywallView.swift](../App/PaywallView.swift) — NavigationStack / ScrollView
- [PeopleManagerSheet.swift](../App/PeopleManagerSheet.swift) — NavigationStack / MemoraList・ネイティブメディア
- [PeopleView.swift](../App/PeopleView.swift) — List / ScrollView
- [PerformanceLogView.swift](../App/PerformanceLogView.swift) — NavigationStack / MemoraList
- [PersonDetailView.swift](../App/PersonDetailView.swift) — List
- [PersonEditSheet.swift](../App/PersonEditSheet.swift) — NavigationStack / MemoraForm
- [PhoneNumberEntryView.swift](../App/PhoneNumberEntryView.swift) — 専用ビュー
- [PhoneVerificationView.swift](../App/PhoneVerificationView.swift) — 専用ビュー
- [PhotoEditorView.swift](../App/PhotoEditorView.swift) — NavigationStack
- [PlaudConnectionView.swift](../App/PlaudConnectionView.swift) — NavigationStack / MemoraList
- [PrivacyStorageView.swift](../App/PrivacyStorageView.swift) — MemoraForm
- [ProfileEditorView.swift](../App/ProfileEditorView.swift) — NavigationStack / MemoraForm・ネイティブメディア
- [ProjectChatRenameSheet.swift](../App/ProjectChatRenameSheet.swift) — NavigationStack / MemoraForm
- [ProjectChatsView.swift](../App/ProjectChatsView.swift) — List
- [ProjectChatView.swift](../App/ProjectChatView.swift) — ScrollView
- [ProjectFilePickerSheet.swift](../App/ProjectFilePickerSheet.swift) — NavigationStack / MemoraList
- [ProjectNoteEditSheet.swift](../App/ProjectNoteEditSheet.swift) — NavigationStack / MemoraForm
- [ProjectPDFView.swift](../App/ProjectPDFView.swift) — 専用ビュー・ネイティブメディア
- [ProjectSourceAddSheet.swift](../App/ProjectSourceAddSheet.swift) — NavigationStack / MemoraForm・ネイティブメディア
- [ProjectSourceDetailView.swift](../App/ProjectSourceDetailView.swift) — ScrollView・ネイティブメディア
- [ProjectSourceOperationCheckView.swift](../App/ProjectSourceOperationCheckView.swift) — MemoraList / NavigationStack
- [ProjectSourcePrivacySheet.swift](../App/ProjectSourcePrivacySheet.swift) — NavigationStack / MemoraForm
- [ProjectSourcesView.swift](../App/ProjectSourcesView.swift) — List
- [ProjectsView.swift](../App/ProjectsView.swift) — ScrollView / NavigationStack
- [ProjectTaskOperationCheckView.swift](../App/ProjectTaskOperationCheckView.swift) — MemoraList / NavigationStack
- [ProjectTasksView.swift](../App/ProjectTasksView.swift) — List
- [RealtimeTranscriptView.swift](../App/RealtimeTranscriptView.swift) — ScrollView
- [RecentlyDeletedView.swift](../App/RecentlyDeletedView.swift) — List
- [RecordingMarkersView.swift](../App/RecordingMarkersView.swift) — 専用ビュー
- [RecordingMethodSheet.swift](../App/RecordingMethodSheet.swift) — NavigationStack / ScrollView
- [RecordPrivacySettingsView.swift](../App/RecordPrivacySettingsView.swift) — NavigationStack / MemoraForm
- [RegisteredLLMEditor.swift](../App/RegisteredLLMEditor.swift) — NavigationStack / MemoraForm
- [RegisteredLLMsView.swift](../App/RegisteredLLMsView.swift) — MemoraForm
- [RenameMeetingSheet.swift](../App/RenameMeetingSheet.swift) — NavigationStack / MemoraForm
- [RenameSpaceSheet.swift](../App/RenameSpaceSheet.swift) — NavigationStack / MemoraForm
- [ResidentAgentEditor.swift](../App/ResidentAgentEditor.swift) — NavigationStack / MemoraForm
- [ResidentAgentsView.swift](../App/ResidentAgentsView.swift) — MemoraForm
- [RootTabView.swift](../App/RootTabView.swift) — NavigationStack / TabView
- [SearchView.swift](../App/SearchView.swift) — NavigationStack / ScrollView / List
- [SettingsBackupView.swift](../App/SettingsBackupView.swift) — MemoraForm
- [SettingsCategoryView.swift](../App/SettingsCategoryView.swift) — MemoraForm
- [SettingsNotesView.swift](../App/SettingsNotesView.swift) — MemoraForm
- [SettingsView.swift](../App/SettingsView.swift) — NavigationStack / MemoraForm
- [SharedProjectView.swift](../App/SharedProjectView.swift) — List
- [SharedRecordView.swift](../App/SharedRecordView.swift) — ScrollView
- [ShareInboxView.swift](../App/ShareInboxView.swift) — MemoraForm
- [SkillDetailView.swift](../App/SkillDetailView.swift) — ScrollView
- [SkillEditorView.swift](../App/SkillEditorView.swift) — NavigationStack / MemoraForm
- [SkillsView.swift](../App/SkillsView.swift) — MemoraForm
- [SlideView.swift](../App/SlideView.swift) — 専用ビュー
- [SpaceDetailView.swift](../App/SpaceDetailView.swift) — ScrollView
- [SpacePickerSheet.swift](../App/SpacePickerSheet.swift) — NavigationStack / MemoraList
- [SpeakerEditSheet.swift](../App/SpeakerEditSheet.swift) — NavigationStack / MemoraForm
- [SpeakerIdentificationSettingsView.swift](../App/SpeakerIdentificationSettingsView.swift) — MemoraForm
- [SpeechRecognitionSettingsView.swift](../App/SpeechRecognitionSettingsView.swift) — MemoraForm
- [StateGalleryView.swift](../App/StateGalleryView.swift) — MemoraList / ScrollView
- [StorageUsageView.swift](../App/StorageUsageView.swift) — MemoraForm
- [StreamingMarkdownView.swift](../App/StreamingMarkdownView.swift) — 専用ビュー
- [SummaryGenerationSheet.swift](../App/SummaryGenerationSheet.swift) — NavigationStack / ScrollView
- [SummaryHistoryView.swift](../App/SummaryHistoryView.swift) — MemoraForm / ScrollView
- [SummaryStyleSettingsView.swift](../App/SummaryStyleSettingsView.swift) — MemoraForm
- [SummaryTemplateDetailView.swift](../App/SummaryTemplateDetailView.swift) — ScrollView
- [SummaryTemplateEditor.swift](../App/SummaryTemplateEditor.swift) — NavigationStack / MemoraForm
- [SummaryTemplateMarketplaceView.swift](../App/SummaryTemplateMarketplaceView.swift) — MemoraForm
- [TaskEditView.swift](../App/TaskEditView.swift) — NavigationStack / MemoraForm
- [TasksView.swift](../App/TasksView.swift) — ScrollView / List
- [TeamCreateSheet.swift](../App/TeamCreateSheet.swift) — NavigationStack / MemoraForm
- [TeamJoinSheet.swift](../App/TeamJoinSheet.swift) — NavigationStack / MemoraForm
- [TeamSharesView.swift](../App/TeamSharesView.swift) — MemoraList
- [TeamTaskBoardView.swift](../App/TeamTaskBoardView.swift) — ScrollView
- [ThinkingOrbView.swift](../App/ThinkingOrbView.swift) — 専用ビュー
- [ThinkingTraceView.swift](../App/ThinkingTraceView.swift) — 専用ビュー
- [ToolsView.swift](../App/ToolsView.swift) — 専用ビュー
- [TranscriptView.swift](../App/TranscriptView.swift) — ScrollView
- [VoiceProfileView.swift](../App/VoiceProfileView.swift) — MemoraForm
- [WebhookEditor.swift](../App/WebhookEditor.swift) — NavigationStack / MemoraForm
- [WebhookSettingsView.swift](../App/WebhookSettingsView.swift) — MemoraForm
- [WebResearchDetailView.swift](../App/WebResearchDetailView.swift) — List
- [WebResearchSaveSheet.swift](../App/WebResearchSaveSheet.swift) — NavigationStack / MemoraForm
- [WebResearchSettingsView.swift](../App/WebResearchSettingsView.swift) — MemoraForm
- [WebResearchView.swift](../App/WebResearchView.swift) — NavigationStack / MemoraForm
- [WorkspaceSettingsView.swift](../App/WorkspaceSettingsView.swift) — MemoraForm
