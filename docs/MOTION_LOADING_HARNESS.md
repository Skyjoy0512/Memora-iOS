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
