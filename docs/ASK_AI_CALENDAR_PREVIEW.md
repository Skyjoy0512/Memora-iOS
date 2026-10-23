# CalendarPreview — 実予定に結び付く日程表示

基点 `b4e99ff`。既存11種類のIntelligent UIに、読み取り専用のCalendarPreviewを追加する。
Google Calendar APIの新規接続ではなく、既存の端末EventKit経路を使う。新しいAPI/サーバー/依存はない。

## データと表示

- read_calendarが実際に取得した予定名（200文字まで）、開始/終了日時、終日設定を、一時UUIDへ割り当てる。
  EventKitの識別子は端末内の重複排除にだけ使い、LLMへ渡さない。
- 1日30件、1回答120件まで。取得件数と参照可能件数を分け、空の結果や上限を事実どおり伝える。
- CalendarPreviewのitemsはreferenceIDだけ。モデルによるtitle/detail/value/actionの指定は拒否する。
  行には取得済みの名称・日時を表示し、日付順で並べる。別回答/未知/重複UUIDは利用しない。
- 終日、複数日の終日、日をまたぐ時刻に対応。終日予定の終了日はEventKitの排他的な終了日時として扱う。
  モノトーンの行表示、システム文字サイズ、VoiceOverの行結合、テキスト選択を使う。
- プレビューから書き込み、URL起動、録音開始は行わない。既存Journalの予定詳細/録音導線はそのまま。
- 同じ繰り返し予定でも開始日時が違う回は別参照。同じ回を再取得した場合はUUIDを維持する。

## 許可と失効

- 端末のカレンダー読取権限と、AIへ内容を渡す権限を分ける。cloudのread_calendarは既存の承認カードで
  対象日・共有項目・最大30件を確認し、承認前は取得しない。changesData=falseで書込承認と区別する。
- 実行前、承認後、取得後にworkspace/復元/保護、現在のregistry/schemaとplugin/person policy、
  カレンダー権限、integration状態、変更revisionを照合する。
- 共有を拒否したread_calendarは同じ回答の中で再要求できない。新しい依頼の承認は別に扱う。
- EventKitの変更通知とアプリ復帰でrevisionを失効させる。実行中に既に予定を読んでいる場合は停止する。
  取得中の変更もrevision比較で拒否し、取得した内容をツール結果へ出さない。
- cloudの各リクエスト直前のisCloudSessionAuthorizedにも同じ照合を追加。
  非cloudでも失効した予定から資料やメール下書きを生成しない。
- 一時参照はAIChatMessageのメモリ内だけ。Codable会話snapshot/バックアップに保存せず、履歴から権限を復活させない。
  予定を根拠としたcloud provenanceは不完全として扱い、関連履歴を外部へ再投入する根拠にはしない。
- EventKit storeをAI読取時だけ保持し、変更通知を受け取る。自動で再取得・外部再生成せず、新しい依頼を必要とする。
  通知の扱いはSDKのEKEventStore.hと[Appleの変更通知](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ekeventstorechanged)を確認した。

## 検証

`bash tools/checks/run-artifact-provenance-checks.sh --calendar-interface`

本番readCalendarTool、承認waiter、registry/schema/policy、プレビュー対象の検索、cloud送信直前の認可、
資料生成の認可を、架空のEventKitサービスと一時SQLiteで検証する。
実EventKitとregistry組立、承認ボタン入力はmockであり、端末の実予定は取得しない。

- cloud承認前は取得0回、拒否時も0回。読取専用の承認でdidChangeDataを増やさない。
- IDと実予定の一致、他message/未知ID/重複IDの拒否、繰り返し予定のUUID維持、空結果、上限、不正日時。
- 取得中の権限/設定/registry/workspace/revision変更、復元、message消失、キャンセル。
- 表示時とcloud送信前の失効、失効した予定を使うartifact生成の拒否。
- CalendarPreviewの未定義操作/モデルによる予定名や日時の上書き拒否、完成したcomponent単位のstreaming。
- 既存snapshotの読込と新しい一時参照が保存/復元されないことを確認。

Debug表示確認画面の予定は架空データであり、本番の表示部品だけを共有する。
実EventKit通知/権限ダイアログ、実cloud通信、実機VoiceOver/性能、カレンダーごとのAI共有設定は未検証または未実装。
最終ビルド・テスト・画像の結果はASK_AI_2_VALIDATION.jsonのcalendar_preview_followupに記録する。

最終Debug preview / Release simulatorは両方成功（各11件の既存警告）。
ログは `2026-10-17T17-19-46-b3c86e07.log` / `2026-10-17T17-19-47-b6efdd3f.log`。
指定3runner、新しいcalendar-interface runner、JSON/diff検査は成功。
実際のDebug bundleのMinimumOSVersion=26.0と、更新したカレンダー利用目的も確認した。

最終Debugの架空表示: [Dark](qa/askai2/calendar-preview-dark.png) /
[Light](qa/askai2/calendar-preview-light.png) / [最大文字](qa/askai2/calendar-preview-large-text.png)。
最大文字ではReduce Motionも有効にして確認。終了後はDark/large/Reduce Motion無効に戻し、
元のHomeと `[@ジャーナル分析]` のdraftを保持した。以前からのAX取得問題は未解決として扱い、
今回は画像/座標で確認した。実VoiceOverの読み上げを確認したとは扱わない。

## 2026-10-24: 読取の会話世代と承認中の失効

上記の2026-10-17結果は履歴であり、今回の検証とは区別する。

- 本番`readCalendarTool`を通す回帰テストで、取得待ちの途中にrequest IDが
  置換されても、旧結果を受理する不具合を再現した。
- 既存`AgentConversationExecutionContext`を再利用する`CalendarAgentReadContext`で、
  request/message/ワークスペース世代/policyと、承認前に固定したcalendar revisionを検証する。
  承認後・取得後に失効していたら内容を返さず、一時snapshotも作らない。
- EventKitの変更監視は承認待ちに入る前に開始する。監視の開始だけでは予定本文を取得せず、
  cloudの取得には従来どおり個別の承認が必要。
- カレンダー連携のON/OFFが実際に変わった時は、既存revisionを同期的に失効させる。
  OFF→ONで過去のプレビュー/後続cloud送信/資料作成を復活させない。
  同じ値の設定では不要に失効させず、新しい依頼と承認で正常に取得し直せる。
- 旧request・settled/別message・別workspace世代のコールバックは、今のtraceやblocked toolsを
  更新しない。既存のschema/registry/person policy、Gmail/MCP由来の許可も再確認する。
- 54の状態変更ケースと新しい依頼での復旧を、架空EventKit/会話状態と本番domain・approval
  waiter・registry・権限処理で確認。実予定や実ネットワークを利用した検証ではない。

新しいUI部品や権限scope、カレンダーの書込経路は変更していない。
`create_calendar_event`のOS権限待ちをまたぐ保存境界、実EventKit通知の到達/取消、実機UI、
カレンダー単位のAI共有設定は別の未完了項目として残る。
今回のビルド・UIテスト結果は`qa/memora-1.0/phase6/calendar-context-validation-summary.json`を参照。
