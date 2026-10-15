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
