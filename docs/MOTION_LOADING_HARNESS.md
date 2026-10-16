# Motion / Loading / Native Harness 改善（2026-10-16）

## Phase 0 — 現行監査

基準: `5dc9774a5e8cbf2ca6994c7698618f8a69240504`。GitHub main、Bitrig origin/main、ローカルmainの一致をfetchで確認。開始時クリーン。iOS 18、iOS SDK 27.1。設定・保存形式の変更は予定しない。

全Appのanimation / withAnimation / transition / opacity / offset / scaleEffect / blur / matchedGeometryEffect / matchedTransitionSource / navigationTransition / phaseAnimator / contentTransitionを検索した。分類:

| 種類 | 現行箇所 | 判断 |
|---|---|---|
| 保存情報の初回表示 | Home、MeetingDetail、MeetingNotes、MeetingTranscript、CollapsibleInsightSectionのmemoraTextReveal/Appear | 除去。データ到着と関係なく0.75秒の行・文字リビール、最大0.2秒のセクション遅延がある |
| 静的案内の初回表示 | Auth、Paywall、AIQuestion、AskAIGreeting、ManualAIProcessingCard | 除去。初回表示で待たせる価値がない |
| 議事録セクション | id(selectedSection)、scale/opacity transition、親VStackのanimation | identityの強制破棄と親全体のアニメーションを除去。native picker、editor draft、player所有位置を維持 |
| 操作・ナビゲーション | RootTabView、ProminentTabBar、Create popover、Hero、展開、再生bar、undo | 保持。UISegmentedControl、glass、zoom、composerは変更しない |
| 検索結果・予定の入替 | SearchViewの結果ID animation、Libraryの予定ID animation | 除去。操作コントロールの動きと分離 |
| 処理中のみの表示 | ShimmerText、PixelLoader、WorkingStatus、ProcessingOverview | 再利用。実進捗・本物の開始時刻・承認待ちを維持 |
| AI本文 | AIResponseText live Text → settled Markdown、StreamingTextの未使用word timer | 同一ブロックrendererへ。固定word待機を廃止 |

追加観察:
- Homeは古いリクエストの**代入**を防ぐが、既存calendarEventsと対象日付が結びついていない。次の日の取得中、前日の予定がrecap/summary/timelineへ入る。
- ProjectSourceDetailは参照名だけをtask IDにし、開始時に本文を消す。source ID・参照名・retry IDを束ね、取消後の反映を防ぐ必要がある。
- AgentConversationLoopは16往復/24操作、ID重複防止、都度認可が既存。時間・累積出力の予算が不足。既存registry/discovery/approvalを作り直さない。
- ConversationScrollStateは手動閲覧を維持するが、streamによるheight増加を未読として扱わず、onAppearで常に末尾へ移動する。

## 検証方針

実ユーザーデータ・キー・有料モデルを使用しない。既存host fixture（next-generation / plugin / persistence / optimization）と追加の純粋Swift fixtureを使用。Bitrig iOSプレビューで表示確認する。実機Releaseの起動・hitch・memory・外部接続は別検証とし、host CPU値から改善率を推定しない。

Phase 1〜6の結果、比較表、残課題は各段階で追記する。

## Phase 1 — 即時表示

保存情報・静的案内のAppear/TextRevealの利用を全除去。MemoraMotionとTextRevealRendererの共有定義は保持。議事録セクションの強制id/transitionと親への状態animation、検索結果・ライブラリ予定の一括animationを除去。editor/playerの所有場所とdraft保存は変更しない（switch枝の既存ライフサイクル自体は維持）。Glass picker / Tab / FAB / Hero / composerには変更なし。

検証: `check-motion-policy.py`成功、既存`run-next-generation-checks.sh`成功、iOS preview成功（08-29-44-9398b69f）。既存AppIntents metadata警告1件。Project.jsonにはXcodeテストターゲットがないことを`bitrig test -list`で確認。初回baseline buildはpreviewにより待機、結果は別記。

## Phase 2 — 領域単位のLoading

`MemoraLoadingState`はidle/loading/loaded/empty/failed/refreshing。`MemoraLoadSnapshot`はデータのキーと要求tokenを分け、同一対象の更新は本文を保持し、古い成功・失敗・取消を拒否。`MemoraLoadingContainer`は180msまで不可視の安定領域、180msから静的skeleton、2秒から説明、5秒から実装側が渡した取消操作。空/失敗にskeletonを残さず、本文を行単位でアニメーションしない。モノトーン・静的skeletonなのでReduce Motionでも同じ。ShimmerTextのみ既存の水平shimmerを1.6秒へ統一。

ソース: title/format/取得日時は即時、本文だけ非同期。sourceID/参照/retryをtask IDにし、既存の取消対応readAsyncを再利用。本文更新中は保持、読込失敗/停止は再試行。別sourceの内容を描画しない。Web取得の既存明示操作・停止は維持。

Home: 予定を日付/カレンダー設定へ関連付け、recap/summary/timelineすべて同じ一致した予定を使用。taskの自動取消、要求token、反映前の再確認を併用。復帰/EventKit通知もtask IDで更新。ローカル記録は待たずに表示。CalendarServiceの既存APIは失敗と空を区別しないため、新しいエラー原因を推測して表示しない。

検証: virtual clockの50/150/180/200/2000/5000ms、古い応答、重複要求、取消後応答、retry、refresh保持、日付key、empty/failedを`LoadingPolicyChecks`で成功。scroll既存チェック成功。iOS preview成功（08-31-41-be522b3b、最終差分を含む08-33-33-5396a777）。実時間の遅延を注入した画面検証は未実施。

## Phase 3 — Streaming / Markdown / Scroll

`StreamingMarkdownView`はlive/settledで同一のblock viewを使う。view-localの派生cacheで初回から同期表示し、Observableの余分な更新を発生させない。`IncrementalMarkdown`は新しい改行だけを走査し、fenceの外の空行でprefixを確定、未完段落だけを再解析。完成時は残ったtailだけ確定し、全文リビールしない。ストリームの一時本文をMarkdownBlockParserのsettled cacheへ投入しない。100msのネットワーク公開制御は変更なし。

コードfence（backtick/tilde、長いdelimiter、未完了）はliteralなmonospaceとして共通parser/viewへ追加。コード内の見出し・表を解釈しない。編集は既存source editorで可能、コードblockのtapによる新しい編集機構は追加しない。コピー・選択とMarkdownBlockWriterのroundtripを維持。CRLFの空行も同一解釈に修正。

AIMessageViewはstreaming/settledの分岐による本文viewの入替をやめ、引用リンクも同じ経路で描く。無効な資料番号は既存の検証で除去。NativeAIInterfaceのschema/権限/完了待ちを変更せず、完全受信時のUI追加だけ許す。表の未完行・inline構文が完成した時の**tail内**のサイズ変化、Native UIが新規追加された高さまでゼロにはできない。

StreamingTextの固定60ms/word、FlowLayout、blur、NLTokenizer、timerを除去し、互換wrapperを保持。新しい文字は到着時に表示（追加fadeもなし）。本文開始後はstatusのshimmerを静止textへ替え、承認待ちは従来のisWaitingを維持。

Scroll: 手動閲覧中のheight増加を未読として記録、生成中にも「新しい回答」を出す。再appear時は追従中だけ末尾へ移動。キーボード/measurementの変化で追従意図を変えない。タブでview自体が破棄される場合の任意位置復元までは追加していない。

検証: motion/loading/scroll/増分Markdown fixture成功。next-generation全体再実行成功（snapshot、privacy、Native UI validation、stream終端/partial tool、plugin approval/costを含む）。iOS preview成功（08-35-19-69a4ef65）。有料ネットワーク・実機ストリーミングは未実施。

Host Swift -O、架空18,130 bytes、92更新、11回: 全文を毎更新parseする候補の中央値22.125ms/p95 34.541ms、増分2.546ms/3.036ms（全92更新の合計）。解析入力848,098 → 20,993 bytes。`MarkdownStreamingBenchmark.swift`で再現可能。**旧live Textのbefore/after値ではなくparser戦略の比較**。旧liveはそもそもMarkdown未解析。実機のフレーム、初回到着時間、memory改善率へ外挿しない。

## Phase 4 — 情報設計の最小修正

検索のpromptをジャーナル/プロジェクト名/ソース名/チャット名へ明確化。キーワード検索は既存local処理、AI質問は明示ボタンのまま。プロジェクトのソースfooterで追加の次の操作と本文/送信許可の範囲を説明。YouTubeはmetadata取得と音声/字幕未取得を明示（失敗理由も残す）。Notionの操作一覧に混入していたMemora内検索ツールを除外し、実装済みのページ作成だけ表示。未実装Drive/GitHubの接続表示は増やさない。

| 検索面 | 現行対象/方式 | 範囲・順位・遷移 |
|---|---|---|
| Home | 全日付のjournal、既存contains | 現workspaceのローカル閲覧。日付絞込と検索を区別、記録へ遷移 |
| Library Files | 録音のsearchText、contains | 現workspace、並替/絞込を維持、record詳細 |
| Library Projects | project名、contains | 自分と共有snapshotは別section、共有はread-only |
| Ask AI内キーワード検索 | 会話の検索用text、task title | 会話/タスクにgroup、直接遷移と明示的な「Memoraに聞く」を分離 |
| Project Sources / Chats | source/workspace item名 / chat名、localizedStandardContains | project IDで先に限定。本文全文検索とは表示しない |
| ProjectのAI根拠検索 | SQLite FTS5と既存日本語ranking | ProjectContextBuilder/RecordAccessPolicyによる許可範囲だけを索引・取得、引用からpage/source/recordへ |
| 過去AI履歴 | question/answer/scopeLabel、幅/大小正規化 | 保存済み履歴、継続操作。外部再送時はprovenanceを再確認 |

ローカルで自分の記録を読む権限と、外部AIへ送信する許可は別。共有/他workspaceを横断する新しい索引は作らない。全文キーワード検索の統一・新たな大量データ索引は未実装（既存FTSの品質/速度検証を維持）。意味の異なるempty/failureを巨大共通ViewModelに統合しない。

検証: CatalogPresentationChecks、ProjectSourceAvailabilityChecks、plugin/privacy/navigation一式成功。iOS preview成功（08-37-43-97dc2765）。チャット検索の最終prompt文字列は統合ビルドでも再検証する。保存・権限・課金処理に変更なし。

## Phase 5 — Native Harness

公式資料・revision・機能ごとの8観点比較・A/B/C評価は [NATIVE_AGENT_HARNESS.md](NATIVE_AGENT_HARNESS.md)。Aを採用。直接連携PoCは必要性を確認できず実施しない。任意コード/plugin loader、Web UI、Node runtime、外部serverは導入しない。

AgentSessionBudget、AgentRunEvent、既存loopの時間境界確認、CloudAgentSessionの要求/累積bytes上限と非stream応答の受信上限を追加。実行履歴の形式、BYOKのKeychain、権限・承認経路、Skill/MCP/registryは維持。metadataだけを既存診断logへ追加。新たな自動LLM呼出しなし。

AgentBudgetChecks（負数/overflow/期限境界/累積bytes/16要求）とAgentConversationLoopChecks（期限後のtool拒否/event事実/取消/revoke/replay）成功。iOS preview成功（08-40-19-7ebecd1d）。料金の厳密なドル上限、provider token使用量、実API互換性・請求額は未検証。ローカル上限を金額保証とは扱わない。

## Phase 6 — 最終検証

### 成功

- `bash tools/checks/run-motion-loading-checks.sh`: motion / virtual-clock loading / scroll / incremental Markdown / honest catalog / session budget。
- `bash tools/checks/run-next-generation-checks.sh`: 変更後に全体成功。mock agentの順序/期限/revoke/cancel/replay、snapshot互換/復元時のgrant拒否、partial toolを実行しないstream、Native UIのschema/権限、source/FTS/Office/Web、plugin/cost/認証、Resident/Widget deeplinkなど。
- `python3 tools/checks/run-optimization-checks.py`: 全体成功。SQLite旧bytes/rollback/並行保存、LocalStore/RecordStore、cache/集計、ProjectSearchIndex、context/privacy、ShareInboxなど。
- NativeAIInterfaceChecksを最終のpartial marker修正後にも単体実行して成功。未完のmemora-ui識別子を表示せず、通常code fenceは維持。
- 最終Debug iOS preview成功: `08-45-18-019d663f`。Release iOS Simulator build成功: `08-46-46-2b142d8a`。App・Widget/Share extensionを含むビルド。既存AppIntents metadata警告1件。
- `git diff --check`成功。保存形式・Project.json・Info.plist・entitlements・Keychain方式は変更なし。実APIキー/個人の記録をfixtureに利用せず、ネットワーク課金なし。

### Simulatorで直接確認した範囲

iPhone 18 Pro Max / iOS 27.1。Home・Library/Projectsのchromeを観察。既存記録の作成/編集/削除は行わない。Settings > プロトタイプ > 状態と復旧 > Loading・本文表示を確認に、DEBUGだけの`MotionLoadingGalleryView`を追加（model/file/networkなし）。

- 初期状態のtitle/control即時表示、50ms成功、6秒取得の静的skeleton、2秒後の説明、5秒後の停止ボタンの出現。
- 既存fixture本文を保持した失敗表示とretryボタン、200msの再試行成功・error消去。
- 日本語・見出し・箇条書き・引用・表・literal code・12段落の合成stream。末尾追従を確認。手動で先頭に戻った後の生成では先頭を保持し、生成中にも「新しい回答」を表示。さらにchunkが届いても先頭に留まり、そのボタンで末尾（scroll 99%）へ戻りボタンが消えた。
- Light/Dark、最大Accessibility Dynamic Type、Reduce Motion/Transparency有効時のfixture描画を確認。見出し・操作がwrapし、静的skeletonの方針を保持。表示設定はLight/large/Reduce Motion・Transparency無効へ戻した。
- 高頻度更新中にSimulator UseのAX取得が一時失敗する場合があり、screenshotと完了後のAXで補った。6秒fixtureの停止操作は短い操作窓で取り逃したため、**停止ボタンの出現と、純粋Swiftでの取消保証を確認したに留まり、UI取消操作成功とは報告しない**。

### 未検証・未測定

| 項目 | 状態 |
|---|---|
| iPhone実機Release起動/Home/tab/detail/Animation Hitches/frame/main thread/peak memory | 未測定 |
| 実ネットワーク初回テキスト/再描画数/本番skeleton表示頻度 | 未測定。100ms制御は変更せず |
| 実会議でsummary/transcript/note編集・再生・Hero/scroll位置の全組合せ | 未検証。static guard/compile/関連fixtureのみ |
| 実EventKitの遅延/権限失敗、実source読込失敗の画面 | 未検証。key/token fixtureとsource reader検証のみ |
| 小型iPhone/VoiceOver音声読み上げ/keyboard/タブを跨ぐ任意位置復元 | 今回のUI操作では未検証。AX読み取りはVoiceOver読み上げの代用ではない |
| 実provider/MCP/Gmail/承認による外部write/課金額 | 未検証。mockで権限・拒否・cost/revoke/cancelを検証 |
| 実機録音/文字起こし/話者/Omi/通知/Widget表示/Live Activity/Dynamic Island/App Intent実行 | 未検証。既存コード保持、compile/host fixtureのみ |
| 実バックアップの復元 | 未実施。既存codec/SQLite rollback/旧snapshot互換のfixture成功と区別 |

Xcode test targetはProject.jsonに存在せず、`bitrig test -list`はexit 78。この理由でxcodebuildへ切り替えず、既存host検証を使った。中間のpreview `08-42-47-af2d7166`は新previewに置き換わったものでcompile失敗ではない。全項目を実機合格とは扱わない。

### 残課題の優先順位

1. 実機Releaseで起動/遷移/scroll/完了前後のhitch・memory・first textの計測。隔離fixtureとInstrumentsで比較する。
2. 小型画面・VoiceOver・keyboard・実会議編集/再生のUI回帰。独立テスト用storeでcalendar遅延・UI取消・restoreを検証する。
3. provider別usageとtoken上限の互換性検証、BYOK API側予算、Memora Intelligenceを接続する場合のserver強制予算。
4. タブのviewが破棄される場合のscroll anchor復元、長大な単一段落/大表のtail解析負荷、全keyword検索のFTS化は計測に基づき別対応。
5. Native pluginに共通version/lifecycle契約を追加するのは、実際の新providerが必要になった時。外部Harness B/Cは固有の価値・採算・認証要件を確認してから。

外部サービス契約・デプロイ・Apple Developer設定変更は不要で、今回実施していない。すぐに必要なユーザー固有の設定操作はない。将来の実API/実機検証には、テスト専用credential/deviceと利用者側の予算設定が必要。

## 変更ファイル一覧

| ファイル | 主な変更 |
|---|---|
| [App/AIAnswerFailure.swift](../App/AIAnswerFailure.swift) | 実行予算上限の失敗理由を追加 |
| [App/AIMessageView.swift](../App/AIMessageView.swift) | 生成中と完了後を同じ本文・引用経路へ統一 |
| [App/AIQuestionView.swift](../App/AIQuestionView.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/AIResponseText.swift](../App/AIResponseText.swift) | live/settledで同じ増分Markdown描画 |
| [App/AgentConversationLoop.swift](../App/AgentConversationLoop.swift) | 期限境界と実行event、既存認可/重複拒否を保持 |
| [App/AgentRunEvent.swift](../App/AgentRunEvent.swift) | 内容を持たない要求/実行/終了event |
| [App/AgentSessionBudget.swift](../App/AgentSessionBudget.swift) | 要求回数・時間・累積bytes制限 |
| [App/AskAIGreeting.swift](../App/AskAIGreeting.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/AuthView.swift](../App/AuthView.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/CloudAgentSession.swift](../App/CloudAgentSession.swift) | BYOKの既存providerへ予算・受信上限を適用 |
| [App/CollapsibleInsightSection.swift](../App/CollapsibleInsightSection.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/ConversationScrollFollowing.swift](../App/ConversationScrollFollowing.swift) | 手動位置を再appearで飛ばさず、生成中も新着導線 |
| [App/ConversationScrollState.swift](../App/ConversationScrollState.swift) | 手動閲覧中の本文増加を未読へ反映 |
| [App/ConversationStatusLine.swift](../App/ConversationStatusLine.swift) | 本文生成中の重複shimmerを抑制 |
| [App/EditableMarkdownDocument.swift](../App/EditableMarkdownDocument.swift) | code blockを通常本文へ誤編集しない |
| [App/HomeView.swift](../App/HomeView.swift) | 日付の即時描画、予定の対象key/取消、検索対象の明示 |
| [App/IncrementalMarkdown.swift](../App/IncrementalMarkdown.swift) | 確定prefixと未完tailを分離した増分解析 |
| [App/IncrementalMarkdownCache.swift](../App/IncrementalMarkdownCache.swift) | view内の派生cache、余分なObservable更新を作らない |
| [App/IntegrationCatalog.swift](../App/IntegrationCatalog.swift) | Notionで実行できる操作だけを提示 |
| [App/JournalCalendarRequest.swift](../App/JournalCalendarRequest.swift) | 日付/設定とrefresh世代の分離 |
| [App/LibrarySection.swift](../App/LibrarySection.swift) | project名検索であることを明示 |
| [App/LibraryView.swift](../App/LibraryView.swift) | 予定の更新で一覧を一括animationしない |
| [App/ManualAIProcessingCard.swift](../App/ManualAIProcessingCard.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/MarkdownBlock.swift](../App/MarkdownBlock.swift) | literal code blockを型で表現 |
| [App/MarkdownBlockParser.swift](../App/MarkdownBlockParser.swift) | fenceとCRLFを解析、既存Markdown責務を維持 |
| [App/MarkdownBlockView.swift](../App/MarkdownBlockView.swift) | literal codeを同じrendererで選択可能に描画 |
| [App/MarkdownBlockWriter.swift](../App/MarkdownBlockWriter.swift) | codeのdelimiter衝突を避けたroundtrip |
| [App/MarkdownFence.swift](../App/MarkdownFence.swift) | backtick/tildeの開閉・長さ照合 |
| [App/MeetingDetailView.swift](../App/MeetingDetailView.swift) | 保存内容の即時表示、強制identityと親animationを除去 |
| [App/MeetingNotesContent.swift](../App/MeetingNotesContent.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/MeetingTranscriptContent.swift](../App/MeetingTranscriptContent.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/MemoraLoadSnapshot.swift](../App/MemoraLoadSnapshot.swift) | 対象key/token、refresh保持、stale/取消拒否 |
| [App/MemoraLoadingContainer.swift](../App/MemoraLoadingContainer.swift) | 要求世代ごとの遅延skeleton/説明/取消/再試行 |
| [App/MemoraLoadingPolicy.swift](../App/MemoraLoadingPolicy.swift) | 180ms/2秒/5秒とshimmer周期を一元化 |
| [App/MemoraLoadingState.swift](../App/MemoraLoadingState.swift) | idle/loading/loaded/empty/failed/refreshing |
| [App/MemoraModel+Agent.swift](../App/MemoraModel+Agent.swift) | run終了の実測時間/操作数だけを既存診断logへ記録 |
| [App/MemoraModel+RecordAgent.swift](../App/MemoraModel+RecordAgent.swift) | run終了の実測時間/操作数だけを既存診断logへ記録 |
| [App/MemoraModel+ScopedAgent.swift](../App/MemoraModel+ScopedAgent.swift) | run終了の実測時間/操作数だけを既存診断logへ記録 |
| [App/MemoraSkeleton.swift](../App/MemoraSkeleton.swift) | 静的で低contrastのplaceholder |
| [App/MotionLoadingGalleryView.swift](../App/MotionLoadingGalleryView.swift) | 保存/通信しないloading・stream・scroll検証画面 |
| [App/NativeAIInterface.swift](../App/NativeAIInterface.swift) | 未完memora-ui識別子を非表示、既存検証を保持 |
| [App/PaywallView.swift](../App/PaywallView.swift) | 保存情報/静的案内の初回Appear/TextRevealを除去 |
| [App/ProjectChatsView.swift](../App/ProjectChatsView.swift) | chat名検索と明示 |
| [App/ProjectSource+Presentation.swift](../App/ProjectSource+Presentation.swift) | YouTubeのmetadataと未取得の音声/字幕を区別 |
| [App/ProjectSourceDetailView.swift](../App/ProjectSourceDetailView.swift) | 本文だけの読取/保持/失敗retry/取消・参照照合 |
| [App/ProjectSourceTextRequest.swift](../App/ProjectSourceTextRequest.swift) | source ID・参照・retryをtask IDへ束ねる |
| [App/ProjectSourcesView.swift](../App/ProjectSourcesView.swift) | source名検索と明示 |
| [App/SearchView.swift](../App/SearchView.swift) | 検索結果/応答状態による親全体のanimationを除去 |
| [App/ShimmerText.swift](../App/ShimmerText.swift) | 既存の水平shimmerを共通1.6秒に統一 |
| [App/SpaceDetailView.swift](../App/SpaceDetailView.swift) | source追加と本文/外部送信範囲のfooter |
| [App/StateGalleryView.swift](../App/StateGalleryView.swift) | DEBUG専用fixtureへの導線 |
| [App/StreamingMarkdownView.swift](../App/StreamingMarkdownView.swift) | 安定したindexで同じblock viewを描画 |
| [App/StreamingText.swift](../App/StreamingText.swift) | 固定word待機/blur/timerを廃止、互換wrapper保持 |
| [App/ThinkingTraceView.swift](../App/ThinkingTraceView.swift) | 本文到着後はstatus shimmerを重複させない |

`tools/checks`の追加/拡張: Motion policy、LoadingPolicy、IncrementalMarkdown、ConversationScroll、NativeAIInterface、AgentBudget、AgentConversationLoop、CatalogPresentation、ProjectSourceAvailability各fixture、MarkdownStreamingBenchmark、motion-loading/next-generation runner。すべて合成データで、外部APIは呼ばない。

ドキュメント: 本報告、NATIVE_AGENT_HARNESS.md、PERFORMANCE_OPTIMIZATION.md。最初のbaseline Debug build（08-28-27-f4f24c0b）も成功した。コミットはPhase 0〜5で33ef840 / 87e99b6 / 5636776 / ff39575 / 017b859 / 6e27053、Phase 6は完了報告参照。pushは実行していない。

## 追加検証 — 取消と読込ライフサイクル（2026-10-16）

基準 `203a3d0`、main、開始時クリーン。本文読込のTask所有と状態反映を`ProjectSourceTextLoader`へ分離し、ProjectSourceDetailViewとDEBUG fixtureの両方で使用する。stopは要求tokenを失効させて即座に停止理由/再試行を表示し、その後Taskを取消す。非協調的なreaderが遅れて成功/失敗しても表示を戻さない。参照名・sourceの再確認はviewから渡すクロージャと既存tokenの両方を維持。端末内ファイルの読取に変わりはなく、保存形式・権限・外部送信に変更なし。

LoadingContainerは表示段階を要求ID/状態へ関連付ける。前の長い要求で到達した5秒段階を、次の高速要求の最初の描画に引き継がない。ConversationScrollStateは、ユーザー操作phaseでもoffsetが変わらずlayoutだけが変わった場合、追従意図を変更しない。指を置いたままのkeyboard resize/本文成長をfixtureで確認する。

DEBUG画面は同じ本番loaderへsleepだけのreaderを注入する。手動停止用の最大60秒待機を追加し、短い停止可能期間に依存しない検証へ変更。保存しないTextFieldと完了操作でkeyboardを確認可能にした。実ユーザーデータ・キー・ネットワークは使用しない。

追加host検証: `ProjectSourceTextLoaderChecks`成功。実際のloaderとsuspendしたmock readerを使い、A→Bの古い成功、同一sourceのrefresh保持、即時stop、stop後の成功、同じ参照のretry、参照失効、失敗、empty、parent Task取消、古い失敗、新しいTaskを古い完了が消さないこと、取消済み開始の拒否をsleepなしで検証。`run-motion-loading-checks.sh`に組込み。scrollのlayout-only regressionも追加して成功。既存`run-next-generation-checks.sh`全体成功。

追加UI確認（iPhone 17e / iOS 27.1、空の別simulator環境）:

- Homeの実際の下部composerで日本語keyboardの表示を確認。送信しない。小型画面でcomposer/toolbarの位置をscreenshotで確認。
- メニューを開いてもkeyboardが残る問題を観察したため、RootTabViewのsidebar表示変更時に既存`composerDismissRequests`だけを送るよう修正。タップとedge gestureのどちらにも同じbindingから適用。入力field/選択/IME制御/保存形式は置換しない。
- 修正後、メニュー表示でAXのkeyboardが消えることを確認。空の小型simulatorへ入力した合成draft（`fixturedraft`）はメニュー開閉後も残った。送信せず、native入力の全選択/削除で消去し、placeholderへ戻ったことを確認。実ユーザーのdraftは使用しない。
- DEBUG fixtureで本番ProjectSourceTextLoaderを用い、静的skeleton、5秒後の停止、停止直後の理由/再試行表示、200ms再試行成功を操作して確認。停止表示のためにreader完了を待たない。前回の「UI取消操作成功は未確認」はこのfixture範囲で解消。実ファイルI/Oの取消操作成功とは区別する。
- DEBUGのnative TextFieldでkeyboard表示と完了ボタンによる非表示を確認。検証fieldは保存されない。
- 最大60秒の合成読込を開始してback、再度fixtureを開くとidle/50ms初期選択へ戻り、旧本文/停止表示/進行中表示がないことを確認。late resultの厳密な拒否は上記suspended-readerテストで確認。

端末切替直後はactive simulator一覧が空/画面が白の期間があったが、後にiPhone 17eのonboarding/アプリを操作できた。取得範囲のrun logにfatal/crash記録なし。クラッシュ原因・起動時間とは断定しない。復帰後はBitrig CLIによる強制再起動を行う必要がなかった。

最終Debug preview成功: `09-07-11-a0111906`。最終Release iOS Simulator build成功: `09-08-58-b2658749`。既存AppIntents metadata警告のみ。motion-loading runnerとnext-generation runnerの成功、`git diff --check`成功。実機の計測・実provider課金・VoiceOver音声読み上げ・実録音/Omiは引き続き未検証。

追加変更ファイル: ProjectSourceTextLoader（新規、Taskとsnapshot所有）、ProjectSourceDetailView（読取をloaderへ委譲）、MemoraLoadingContainer（表示段階を要求へ束縛）、ConversationScrollState（layout-only時の追従意図保持）、RootTabView（sidebarでkeyboard解除）、MotionLoadingGalleryView（同じloaderでの取消とkeyboard検証）、ProjectSourceTextLoaderChecks（新規）、ConversationScrollChecks、run-motion-loading-checks.sh。本追加の本文読込コミットは`997e79f`。スクロール/メニュー修正のコミットは本追加の完了報告参照。


## 追加検証: Markdownの途中状態とツール引数の確定境界（2026-10-16）

- `CloudAgentTurnDecoder.swift`を追加し、`CloudAgentSession.swift`と`CloudStreamAccumulator.swift`の応答検証を揃えた。不正な引数を空objectとして実行可能にしない。完了理由/全callを検証してから履歴と既存承認経路へ渡す。実装と公式資料の根拠は[NATIVE_AGENT_HARNESS.md](NATIVE_AGENT_HARNESS.md)の追加監査参照。
- `CloudAgentTurnChecks.swift`を新設し、`CloudStreamChecks.swift`と`run-next-generation-checks.sh`を拡張。正常な空引数と不完全な引数を区別し、mockの実loopで不正batchのtool実行0件・追加要求なしを確認した。
- `IncrementalMarkdownChecks.swift`を拡張。全fixtureを1/7/37 Unicode scalar単位で分割し、各更新のblocksが実際の完成文書parserと一致すること、settled部分が変わらないこと、完了通知だけではblock構造が変わらないことを確認した。日本語、結合文字、家族emoji、CRLF、checkbox、表、リンク、backtick/tilde fence、未完了構文を含む。Markdown本体と100msの更新間隔は変更していない。
- 成功: `run-motion-loading-checks.sh`全件、`run-next-generation-checks.sh`全件、追加stream/decoderチェック個別実行。初回のnext-generation実行は実行中のscript編集で末尾の構文読取が失敗したため、scriptを固定して全件再実行し終了コード0を確認した。テストの全入力は架空データ、実API/個人記録/キーは使用していない。
- 成功: `bitrig preview -platform iOS`（Debug、iOS 27.1 simulator SDK、iOS 18 deployment target）。起動後のJournalと既存3タブ/下部composerのAXを確認。AppIntents依存のないextensionのmetadata extraction警告が1件あり、今回のSwiftコンパイルエラーはなし。
- 未検証: 実providerへの接続、実iPhone、VoiceOver音声操作、本変更に対するフレーム時間/メモリ/金額の実測。UI配置・Liquid Glass・FAB・保存形式は変更していない。`bitrig build -destination generic/platform=iOS Simulator -configuration Release`も成功（同じextension警告1件）。実機Releaseの測定値ではない。
