# Memora Ask AI 2.0 — 実装と検証

2026-10-17。開始HEAD `f28116c`、fetchしたGitHub main `13af297`。
追加指示を長期記憶/人物/資料/Research/メールの既存開発範囲へ統合した。
[OSS監査](ASK_AI_2_OSS_AUDIT.md)と[機械可読の検証結果](ASK_AI_2_VALIDATION.json)を参照。

## Phase 1 — iOS 26 / 監査

- Project.jsonのproject-level iOS minimumを26.0に変更。アプリ/Widget/Share Extensionの
  実ビルド成果物Info.plistもMinimumOSVersion=26.0と確認した。
- `c3fdd84`。AGENTS冒頭の最低OSも更新。既存availability分岐の大量削除、
  SQLite/Keychain/媒体/backup変更、Widget/Live Activity/App Intentsの置換は行わない。
- 環境のSwiftは6.4、SDKはiOS27.1。既存Swift5互換language modeでアプリをビルド。
  UIの純粋なparser/cache/summaryのhost検証はSwift6 modeでも成功。
  Swift6.2コンパイラそのもの、iOS26実行環境、全アプリのstrict Swift6移行は未検証。
- 指定3OSSのREADME/manifest/source/example/test/license/dependencyを実SHAで監査。
  第三者コードやアセットを移植せず、独自のネイティブ実装を採用。依存追加なし。

## Phase 2 — 会話 / コンポーザー / Markdown

`9a96098`。

- AIResponseCodeBlock: 横スクロール・選択可能なmonospace本文、言語名、44ptのコピー、
  2秒の成功フィードバック。コード実行機能は持たない。
- AIResponseTable: header/行をGridで描く横スクロール表。Dynamic Type、読み上げのheader/行を維持。
- AIResponseMarkdownBlock: 上記をAsk AIのStreamingMarkdownViewへ接続。
  会議要約の編集用MarkdownBlockView/MarkdownBlockWriterは保持した。
- AIComposerBar/QuickAIComposer: グローバル回答中は同じ丸ボタンが停止へ切り替わる。
  入力済みdraftを消さず、既存stopAIChatへ委譲。SearchViewの重複するfloating停止ボタンを統合。
  Web検索オンは「Web」と明示。既存TextField/selection/marked-text/添付/Skills/ガラス/matched geometryを維持。
- ThinkingOrbViewは既存Canvas/速度/Reduce Motionを維持してモノトーンへ統一。
  保存済み内容を隠すText Revealや一列ずつの登場演出は追加しない。

## Phase 3 — 実イベントのAgent Activity

`6dc0cd5`。

- AgentActivitySummaryはAgentStep配列と実行/承認待ち状態だけから件数・失敗・実行せずを導出。
  message.reasoningは入力にも表示にも使わない。生成された進行率・計画を実績にしない。
- AgentActivityViewは1つの開閉行から実toolのタイトル、状態、detail、query/results/outputを確認する。
  直近24step/結果20件/出力8行までの描画に制限し、各stepのIDを保持する。
- ThinkingTraceViewは実行中の既存一行を維持し、実stepがあるときだけ開閉行を表示。
  終了時も結果を確認でき、既定では折りたたむ。明示的に開いた状態は保持する。
  普通の質問に架空のstepを追加しない。
- 出典を開く際は回答に宣言されたID・現在のworkspace/protected/restore状態を再検証。
  Web調査が終了した後も「検索中」と出ていた条件を除去する。
- Shimmerの装飾テキストをAXから除外。SimulatorのAXで見つかった状態文の二重表示を修正する。
  ShimmerそのものとReduce Motionの静止表示は維持。

## Phase 4 — Intelligent UI / ストリーミング

- NativeAIInterface v1の既存8種類を保持し、TaskProgress / MailDraftCard / Disclosureを追加。
  旧履歴は新fieldを要求しない。UI記述は引き続き32KiB/8部品/各30項目/文字数上限を検証する。
- NativeAIComponentStreamはappendされたbyteだけを走査。閉じたcomponentごとに元envelopeの
  完了済みprefix全体をschema/UUID/重複ID/種類/操作の検証へ通す。JSONを推測補完して実行しない。
  各部品のitemが途中なら追加せず、先に完成した部品は同じIDで表示し続ける。
- streaming previewはprompt例のようにversionを先に置くenvelopeを対象にする。
  別のkey順の有効JSONは最終回答で従来どおりdecodeする。最後に全体が不正ならMarkdownへ戻る。
- NativeAIResponseCacheはview-localな描画cache。会話状態・UI書込grant・外部権限は持たない。
  同一text/stream状態の再評価ではJSONを再解析しない。
- AIResponseText/NativeAIInterfaceViewはstream中も検証済み部品を表示し、task完了やmail編集を無効化。
  ForEachのcomponent IDを維持し、stream終了の条件分岐でrenderer全体を作り直さない。
- 無制限の動的tree、式/JS/HTML、任意tool/URL、外部画像/地図取得、汎用form送信は追加しない。
  通常回答は引き続きMarkdownだけでよい。OpenUI Lang互換ではない。

### 対応する構造化部品

| 部品 | データ / 操作 |
| --- | --- |
| TaskList / ActionBar | 実参照task IDだけ。完了はrunAgentTool→registry/承認の既存経路 |
| DocumentCard | その回答が生成した資料ID。既存詳細でpreview/編集/保存/共有 |
| ProjectCard | 読取済みproject IDと既存project navigation |
| SourceList | 実際の送信source。既存記録への遷移 |
| ComparisonTable | 列/行の厳密schema、横スクロール |
| Timeline | title/detailの表示。会議/カレンダーの事実性は元ツールの根拠に依存 |
| Chart | 従来のboundedな棒グラフ。schemaだけで数値の正しさは保証しない |
| TaskProgress (追加) | 許可済みの現task IDから完了数を計算。モデルvalue/action/重複referenceを拒否 |
| MailDraftCard (追加) | 現在のworkspace・この回答のsourceMessageIDに属する実下書きだけ。既存MailDraftSheetで編集/コピー/共有 |
| Disclosure (追加) | 補足title/detailのネイティブ開閉。一時状態だけをviewで保持 |

## Phase 5 — 既存Memora機能との接続

- task完了の既存tool/承認、人物ID/RecordAccessPolicy、project/recordの読取専用範囲を維持。
- interfaceMailDraftはメッセージ一致/保存済みID/workspace/復元中/保護中/Cloud provenanceを確認。
  draft_emailの成功結果に実際の保存済みIDを追加し、モデルが架空IDを作らずMailDraftCardを選べるようにした。
- 会話内のDocumentCard/AgentDocumentCard、Research出典・部分結果・保存、会社書式生成、
  人物の限定Ask AI、長期メモリと出典の経路を再利用する。既存の処理できないソースを利用可能と表示しない。
- モデル出力からのUIは権限にならない。保存履歴に一時的なtask/projectの書込grantを復元しない。
  無許可の自動再実行・実メール送信・追加API/新サーバーはない。
- 実サービスを含む旧/新シナリオA〜Eの全体E2E完了とは扱わない。

## Phase 6 — 検証

- iOS26移行時とUI追加後のDebug preview/Release simulator成功。
  最終のShimmer AX修正・途中表示fixture追加も再ビルドして結果をJSONへ記録する。
- 指定3runner成功: run-next-generation-checks / run-motion-loading-checks / run-optimization-checks。
  cloud-session mock、memory/person/privacy/backup/Office/research/registry/streaming/snapshotも既存runner内で検査。
- 新host検証: IntelligentUIStreamingChecks（完全部品/日本語/escape/途中項目/重複/未知操作/
  容量/置換/cache/旧v1）、AgentActivitySummaryChecks（実イベントの状態）、
  IntelligentUIContextChecks（実context/mail gate、他回答/他workspace、失効、履歴grantなし）。
  contextのdispatch先はspyで、永続変更を実行しない。tool自体の承認/保存は別の既存runnerで検証する。
- Simulator: 架空データの既存/new Debug画面。履歴の開閉、取得情報、コードコピー、Light/Dark、
  最大文字、Reduce Motion、VoiceOver有効時のAX名を確認。元のcomposer draftを保持。
  実ユーザーの記録・メール・会話を送信/編集/削除していない。
- 後述の途中表示固定fixtureも本番response/cache/rendererを使う。実モデルの品質や通信E2Eとは区別する。

### 画像

- Agent表示の同じfixture: [変更前Light](qa/askai2/activity-before-light.png) → [変更後Light](qa/askai2/activity-after-light.png)。
- [変更後Dark](qa/askai2/activity-after-dark.png)。
- 既存Intelligent UIの変更前: [Light](qa/askai2/interface-before-light.png)、[Dark](qa/askai2/interface-before-dark.png)。
- 追加した表示確認画面: [Light](qa/askai2/experience-after-light.png)、[Dark](qa/askai2/experience-after-dark.png)、
  [最大文字](qa/askai2/experience-large-text.png)。別のfixture内容でありpixel単位の同一画面比較ではない。

### 性能の実測と限界

Swift6 modeの最適化host binary、371 UTF8 byte/2componentの同じ確定回答に1,000回アクセス。
今回のfull runnerでは従来の毎回decodeが88.806ms、新cacheが0.095875ms。
focused runnerでは97.639ms/0.1015ms。別のモデルを呼んだ速さ、iPhoneのFPSや消費メモリの改善率ではない。
新stream scannerは日本語を含む1文字ずつの更新を全byte1走査、2部品+最後のenvelopeの3検証で処理する
assertionに成功。descriptorは32KiB、8部品まで。Markdownの既存incremental parserとscroll-followは維持し、
その回帰テストも成功した。

## 残件 / 次の改善

- P0: 実iOS26端末/実機VoiceOverの読み順・発話、日本語IMEの未確定入力、実provider停止のUI E2E、
  長い会話/大量recordでのFPS・memory・energy、録音/背景復帰の実機、実接続を含む全A〜E。
- P1: 実カレンダーIDで根拠付けたCalendarPreview、typed sourceの専用preview、保存済みメール/資料の
  UIからの全経路、行ごとの根拠と生成数値の照合、確認付き長期memory更新、企業Officeの複雑な描画。
- P1: iOS26で非推奨となった認証browser init、MKPlacemark/CLGeocoder等の専用移行と回帰確認。
- P2: 安全なlayout/schema拡張、形式限定form、Line/Pie等、画像の遅延preview、未見コーパス検索評価。
- 正確なprovider請求額上限、Gmail Drafts OAuth、team backendなどは未接続/未実装を維持する。

新しいOSS依存/コード移植/商標素材/実API処理/運営費は追加していない。

### 最終の確認結果

- UI/結合実装: `4f1d9df`。Phase1 `c3fdd84`、Phase2 `9a96098`、Phase3 `6dc0cd5`。
- 最終Debug: `2026-10-17T12-51-39-fb82ffc0.log`、最終Release: `2026-10-17T12-51-40-4db70b10.log`。
  両方成功、各11警告（iOS26の既存API非推奨10件と既存metadata skip1件）。
- [完成部品だけの途中表示](qa/askai2/streaming-component-light.png)を最終ビルドで画像確認。
  次のDisclosure JSONは未完成で表示せず、先に完成したTimelineだけが表示された。
- 最終preview再起動後、AX tree取得が3回失敗したため再試行を止めた。画像取得と操作は継続でき、
  最後の部分表示は画像で検証した。アプリのクラッシュを示す証拠は得ていない。
  Shimmerの重ね文字をAXから外す変更はビルド済みだが、修正後のAX tree/実読み上げは再検証できていない。
- 実機/実サービス/大規模データ・費用の確認は未検証のまま。

### 継続検証 — 参照先の再確認とコンポーザー

基点 `779b2c4`。構造化UIの資料・会議の遷移先とプロジェクトを開く操作で、
現在の回答に宣言されたID・実在・workspaceを再照合する。資料のprovenanceが別workspaceや不正なら
表示と遷移を拒否する。未接続teamの会話と同じworkspace文字列でも、個人SQLiteを参照させない。
個人用の非公開記録をローカルで読む権利と、クラウド送信の権利は分けたままにする。

- 本番の `canOpenInterfaceReference` をhost検証へ組み込み、同じ回答でもIDを取り消した場合、
  削除、未知ID、別回答、復元/保護中、team一致、資料の別workspace、cloud失効を検証する。
- Debugの「コンポーザー（操作の確認）」は本番AIComposerBarとネイティブTextField/入力監視を使う。
  draft・架空の添付参照・送信受付/拒否・停止のcallbackと件数はview内だけに保持する。
  モデルの会話や実APIへ送信しない。架空の添付ボタンはファイルを作成/読み込みしない。
- iPhone 18 Pro Max / iOS27.1で送信試行3回（拒否2・受付1）、停止2回を操作。
  停止と拒否で入力・添付が残り、受付時だけ空になる。英字の追加入力、キーボード上の停止切替、
  Return経由の拒否、受付後のフォーカス維持も画像で確認した。
- [停止後](qa/askai2/composer-stopped-draft.png)、[送信拒否後](qa/askai2/composer-rejected-draft.png)、
  [キーボード表示](qa/askai2/composer-keyboard-draft.png)、[受付後](qa/askai2/composer-accepted-draft.png)。
  終了後は元のHomeと `[@ジャーナル分析]` のdraftへ戻した。確認用draftは永続保存しない。
- AX取得は引き続き失敗したため画像/座標で操作。日本語typeTextはunsupported characterとなり、
  英字入力に切り替えた。既存の日本語draft表示と入力保持は確認したが、IME未確定文字/選択範囲、
  VoiceOverの修正後読み上げは未検証。fixtureの停止callbackは実通信の停止E2Eではない。
- 新規のOSS依存・素材・外部サービス・設定変更はない。ビルドとrunner結果は検証JSONの
  `navigation_composer_followup` に記録する。
- Debug preview / Release simulatorは両方成功。ログは `2026-10-17T13-06-58-511e0487.log` /
  `2026-10-17T13-06-59-5ce5dc8c.log`。各11件の既存警告、エラーなし。
  指定3runnerと拡張したartifact-provenance runner、JSON形式、diffの空白検査は成功。

### 継続実装 — タスク操作の承認後チェック

- 構造化UIからdispatchする時点でも参照範囲を再確認。
- タスク更新は承認後にregistry/schema、plugin/person policyの一致、現在のtaskと会議/project範囲、
  親会議を含むプライバシーを再検証する。未定義キーを含むupdate_tasksを拒否する。
- 本番の承認待機・タスク更新・SQLiteを通すhost統合テストを追加。
  拒否/キャンセル/二重タップ/権限失効/編集/削除/保存失敗/複数taskの原子性を確認する。
- [経路とfixtureの範囲](ASK_AI_INTERFACE_TASK_CHECKS.md)。UIの見た目、データ形式、API料金は変更しない。
  cloud出典のtask更新後は旧contextを失効させ、勝手なgrant更新はしない。再依頼が必要な制約は残る。
