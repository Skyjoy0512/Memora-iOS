# Memora 次世代AI基盤 — 2026-10-14

## 基準と実装方針

GitHub `Skyjoy0512/Memora-iOS` の main を fetch し、開始時のローカル main
`0c2111f` と一致を確認。AGENTS.md、ASK_AI_PLUGINS、AI_PLUGIN_MCP、
MONOCHROME_DESIGN、MAIN_NAVIGATION、PROJECT_WORKSPACE_V2、
PERFORMANCE_OPTIMIZATION、IMPROVEMENT_BACKLOG を照合した。
一部の古いナビゲーション文書のタブ順は現在のコードと異なるため、
RootNavigation と AGENTS.md の Home / Library / Ask AI を基準にする。

既存の空白Ask AI、モノクロ色、資料取り込み、プロジェクトチャット保存、
引用／PDFページ／音声時刻への遷移、承認カード、Gmail PKCE、MCP SDK、
外部費用チェック、BYOK／端末内AI、常駐エージェントは再利用する。
サービスの新規契約・デプロイ・実アカウント読取・有料推論は行わない。

## P0: 会話表示と受信

- AIResponseText をAsk AI／プロジェクト／記録の質問で共用。ユーザーの
  メッセージは既存 aiBubble、回答は選択可能なMarkdown。新規プロジェクト
  チャットの常設説明を外し、スコープ名だけ残す。
- AIEngineService を共有し、クラウドには共通 CloudTurnStreaming を接続。
  CloudAgentSession はOpenAI互換／Anthropic両方のSSEを受信する。
  既存の要約専用 completeStreaming と長文継続規則は変更しない。
- 本文の最初の受信は即表示、その後は最短100ms間隔でまとめる。
  受信中はプレーンテキスト、完了後はMarkdown。受信済み回答を再度
  単語ごとに隠して再生しない。引用リンクは確定した出典だけに付ける。
- プロジェクトの途中本文はメモリ上の専用値で保持し、トークンごとの
  SQLite保存はしない。履歴は正常終了後に既存の別ストアへ1回保存する。
- 分割・並行ツール引数、reasoning、プロバイダー拡張、Anthropic署名を
  保持。JSONオブジェクトとして成立し、終端まで受信したツールだけ渡す。
  EOF、length/max_tokens、不正イベント／JSONは失敗として扱う。
- 2MiB上限、600秒の総時間上限、キャンセルによる接続破棄。
  JSONだけを返す互換サーバーは同じレスポンスを処理し、再課金を伴う
  フォールバック要求やツールの自動再送をしない。
- 記録質問の人工的な850ms待機を除去し、停止ボタンを追加。
  送信時の設定、スコープ、依頼IDを固定する。プロジェクトは現在の資料と
  送信した履歴の根拠を送信前／保存前に再検証し、所属・許可変更を拒否。

Glass、UISegmentedControl、FAB、ルート遷移、コンポーザー、Hero、
BottomBarScrollBehavior、音声／写真ファイル形式、SQLiteスキーマは保持。

## 検証と境界

- CloudStreamChecks: OpenAI互換の分割／順序違いのツール、拡張署名、
  reasoning、Anthropicブロック／署名／JSON、終端、途中切断、壊れた引数、
  サーバーエラー、サイズ上限を固定fixtureで検証。
- 既存 run-ask-ai-plugin-checks.sh の10スイート成功。
- 実クラウドLLM／MCP／Gmail／NotionのE2E、iOS18実機、実録音、Omi、
  frame単位のGlassアニメーション、起動時間／メモリは未検証。
  プロバイダー固有の未知のSSE拡張は成功扱いせず安全に停止する。

一次資料: [OpenAI stream delta](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events)、
[Anthropic stream](https://platform.claude.com/docs/en/build-with-claude/streaming)。

## A2UI導入判断

[A2UI](https://github.com/a2ui-project/a2ui) はApache-2.0、
[A2UI-Swift](https://github.com/BBC6BAE9/a2ui-swift) はコミュニティ製のMIT、
iOS17以降対応で、v0.9/v0.9.1の実装とテストが公開されている。
ただしREADMEのテスト件数は本アプリでの検証結果ではない。
メッセージ処理、式評価、双方向バインディング、メディア／URL、全体の
コンポーネントカタログの監査と、Memoraの承認・課金・権限経路への接続が
必要になる。現時点では依存を追加せず、用途を限定したJSONスキーマと
既存SwiftUIによる小さなレンダラーを優先する。完全なA2UI互換は主張しない。

## 次の境界

プロジェクトチャットはAIEngineServiceでの根拠付き会話を維持する。
グローバルAgentRunnerへ安易に振り替えるとプロジェクト境界が消えるため、
全ツールのproject/record対応が検証できるまでは書き込みエージェント化しない。
中断した外部操作の自動再実行は追加しない。永続ジョブとサーバーの
idempotency照合が必要。クライアント上限は本番の課金保証ではない。

## P1: Intelligent UI の初期対応

`NativeAIInterface` version 1 は A2UI の考え方に沿う独自の限定スキーマ。
32KiB、最大8部品、各30項目、文字数／数値上限、安定IDの重複検査、
UUID、表の列数を検証。未知の部品・キー・操作・URL・コードは拒否する。
通常回答のMarkdownの後ろに任意の `memora-ui` JSONブロックを1つ置く。
本文は既存の履歴文字列としてSQLiteに保存され、旧履歴は変更せず読める。
途中のJSONは表示せず、失敗時は先に書かれたMarkdownへ戻る。

- ネイティブ表示: TaskList、DocumentCard、ProjectCard、SourceList、
  ComparisonTable、Timeline、Chart（Swift Charts）、ActionBar。
- QuestionForm、ApprovalCard、ProgressCardは、既存のAgentQuestionCard、
  AgentApprovalCard、ThinkingTraceViewを使う。AIが作った偽の承認や進行状態
  は表示しない。実行中のリクエストの状態だけ表示する。
- UI選択の指示はクラウドのグローバルエージェントに追加。端末内の小さい
  コンテキストにこの追加Schemaを自動送信しない。プロジェクト／記録の
  AI実行をグローバルの書き込みエージェントに変えない。
- タスク・プロジェクトはその会話で実際に読んだIDだけ参照する。
  資料はそのメッセージで作成したdocumentIDs、出典は既存sourcesに限定。
  タスクの完了操作は原文のモデル再実行なしで既存update_tasksへ渡す。
  元の@制限、現在のレジストリ、1回答24回、書込前承認、ワークスペースと
  タスクの競合検査、SQLite保存失敗時の拒否を維持する。
- UIの値変更とデータ更新は別。承認するまでタスクの表示状態は変えない。
  保存履歴を開き直したときに、古いUIへ書込権限を自動復元しない。
- 比較表とグラフの数値はAIの整理結果であり、Schema検証だけで事実性を
  保証しない。プロンプトで実取得の根拠を要求し、既存本文・引用も残す。

NativeAIInterfaceChecks: 3種の表示モデル、通常／不完全／不正UIのMarkdown
フォールバック、未知の型・操作・キー、負数／Bool、ID不正、重複ID、表の
列不足、32KiB上限を実コードで検証済み。外部クラウドのUI生成、実タスク
変更の承認E2Eはまだ未検証。UIコードのbuild／画面確認は別途記録する。

P1 build: `2026-10-14T11-58-19-6a5ff2fa.log` 成功、既存AppIntents抽出警告のみ。
10既存スイート再成功。iPhone 18 Pro Max のDEBUG表示確認画面で表・横棒
グラフ・タイムラインを確認。これは明示したfixtureであり実AI応答ではない。
Dark + accessibility_extra_large で折り返し、横表、縦スクロール、グラフの
代替数値ラベルを確認。実タスクの作成・変更は検証のためにも行っていない。

## P2: ツール候補検索・手順型スキル・常駐上限

- SemanticToolDiscoveryは名前・説明、日本語2-gramと用途語の端末内検索。
  最大4確認済みサーバー／各40ツールから、関連度を優先して最大16件／24KiB。
  無効・利用不可を除外し、明示指定では指定サーバー内の候補を優先する。
  取得中に接続設定／認証世代が変われば採用しない。外部LLMは呼ばない。
  自動の追加ツール探索・ベクトル検索は未実装。
- 同梱3スキルを維持。カスタム手順はcustom-UUIDで最大30件。本文と選択
  履歴はSQLiteの新しいキー、ON/OFFは既存設定。最大2手順、キーワードで
  自動選択、@を優先。クラウド／端末内の両方へbounded contextを渡す。
- Markdownは32KiB、UTF-8、単純なname/description/tools/keywords/permissions
  frontmatterと本文だけ。完全なYAMLやAgent Skills package互換ではない。
  FileHandleで上限を持ってsecurity scope内で読む。読み込み後に編集画面で
  確認して保存。初期の宣言ツールはMemoraの内蔵AgentTool名に限定し、
  未知ツール／script metadataを拒否する。permissionsは宣言
  データとしてのみ扱う。Shell／Python／JavaScriptの実行経路は追加しない。
- SkillsView、SkillDetailView、SkillEditorViewで用途、手順、利用ツール、
  権限、ON/OFF、作成、編集、削除、共有、最終選択を管理。最終選択は手順
  提供の記録であり実行完了の保証ではない。カスタムスキルと選択履歴も
  バックアップのoptionalフィールドに含め、旧パッケージは空として復元。
  復元前にID・件数・本文の上限を検証し、既存の原子的コミットで確定する。
  記録が空でも既存のカスタムスキルがあれば復元で上書きしない。
- 連携詳細に料金の扱いと利用操作を追加。既存Gmail/Notion/MCPの接続・
  再認証・解除画面を再利用。Drive/GitHub/Google Calendar OAuthは未接続。
- ResidentExecutionLimitsは1実行のAI呼出1〜8、ツール0〜24、読むツールの
  whitelistと通知ON/OFF。旧データは既定値へ復元する。回数上限で途中の
  説明を完成投稿として残さない。未知料金のメール取得は自動実行できない。
  この上限は金額保証や日次課金強制ではなく、BYOKの端末内予防措置。
  iOSの時刻保証なし。将来のサーバーにはResidentAgentの役割／指示／trigger
  とexecutionLimitsを要求として渡し、認証・利用者別予算・idempotencyと
  実状態をサーバーで強制する必要がある。サーバーは契約・配備していない。
  常駐処理を所有するTaskを保持し、設定画面／実行中メッセージから停止できる。
  BGTaskの取消を子Taskへ伝搬し、停止・失敗・途中の結果は完成投稿にしない。

DiscoverySkillChecksとResidentLimitsChecks成功。旧データ復元、Markdown/JSON
往復、未知ツール／script metadata拒否、候補の順序独立性、利用不可／無効／
Schema超過の除外、whitelistで書込権限が増えないことを固定fixtureで検証。
10既存スイートも再成功。初回の保存型／型推論エラーを修正し、
`2026-10-14T12-09-30-7e387ff4.log` build成功（既存警告のみ）。
Files providerでの実インポート、実MCP／BYOK／バックグラウンド通知は未検証。

P2最終コードbuild: `2026-10-14T12-54-11-b8b5861c.log` 成功。
Simulatorで手動作成、保存、詳細の手順表示、無効化、一覧の状態、編集後の
名前と無効状態の維持を確認。直接setValueではネイティブ入力が確定せず
保存に失敗したため、通常のキー入力に切り替えて確認した。
検証用QAUpdatedだけを作成。P3の再起動後に名前と無効状態の復元を確認し、
確認ダイアログを経てその1件だけを削除。一覧の内蔵3件の維持も確認した。
既存の記録・同梱スキル・接続設定は変更していない。

## P3: システム導線とウィジェット

- MemoraAppLinkのローカルURLを共有。Ask AI、Journal、タスク、今日取り組む
  タスク、メモ編集、プロジェクトへ既存NavigationStackで遷移する。既存の
  task/meeting/capture/recordingリンクを保持。新しいURLはパス、UUID、
  query/userinfo/port/fragmentを検証する。URLに質問・記録本文を載せない。
- App IntentsはAsk AI／録音開始／メモを書く／今日のタスク／ジャーナル／
  プロジェクトの6種。AppDelegateと同じ唯一のモデルをAppDependencyManager
  で注入。録音はforegroundで既存startCapture・マイク許可・ドラフト保存を
  通り、isRecordingかつ非一時停止を確認する。ロック／保存保護／復元中は開始しない。
  メモは編集画面を開くだけで保存を自動実行しない。
- プロジェクト名をSiri等の候補に出す設定は初期OFF。名前・IDだけを
  current personal workspaceから最大100件。Face ID設定／保護／復元中は
  候補を返さない。OSに提供した名称のキャッシュ完全消去は保証しない。
- Ask AIウィジェットは小・中とロック画面の3サイズ。独自URLで新規会話を
  開き、共有コンポーザーへ一度だけフォーカスを要求。QuickAIComposerの
  変更はその引数1行だけ。Glass、IME、展開、タブとFABの実装は保持。
- 今日のMemoraは日付／未完了件数、mediumでは記録件数／次の予定の時刻。
  プロジェクトはoptional AppEntityで指定でき、名前／タスク件数／最近の
  記録の作成日を表示。資料更新日を取得したかのようには表示しない。
- Shared snapshotは64KiB、20プロジェクト、8時間・同日限り。SQLite、
  音声、写真、本文、予定名をExtensionへ渡さない。件数／名前／予定時刻は
  個別opt-in。チーム・App Lock・保護・復元では破棄、private項目には
  privacySensitive、ファイルはcompleteFileProtection。350msでまとめ、
  WidgetKit更新にLLMを使わない。未設定／古い／壊れたデータは未取得表示。
- 既存クイック記録・録音Live Activityを保持。Controlの表示を「Memoraを
  開く」に合わせ、録音開始と区別。録音終了は既存のimmediate終了、起動時
  は既存endStaleLiveActivities。録音後の文字起こし状態は追加していない。

### 現ビルドの設定境界

Project.jsonとbundle IDは変更していない。現在のIDはscaffoldで、App Group
とMemoraWidgetAppGroupは未設定。そのためデータウィジェットは実装・build
済みだが件数やプロジェクトの情報共有は動かない。設定画面はその状態を
説明し、共有スイッチを無効にする。Ask AI／既存クイック記録は共有不要。

本番の識別子へ移すとアプリのsandboxが変わり、既存データの移行が必要。
既存ユーザーのバックアップ・復元を先に実証し、公式の識別子割当、同じ
group.<host-bundle-id>のentitlementとInfo値をApp／Widgetに設定する。
SQLiteをApp Groupへ移す必要はない。公開に進める作業やAppleアカウント
設定は今回行っていない。

AIタスクLive Activityは今回は未実装。端末の会話がbackgroundで継続する
保証がなく、実行基盤・停止・承認・期限切れを紐づけず進行中を表示しない。
サーバージョブを導入する場合はActivityのstaleDateと終了を実状態に接続し、
実行ID／再接続／idempotencyを先に検証する。新規サーバーは配備していない。

[Apple OpenURLIntent](https://developer.apple.com/documentation/appintents/openurlintent)
はcustom schemeに対応しない。今回はそのAPIへmemora://を渡さず、Widgetの
widgetURLとforeground App Intentsのモデル操作に分けた。

## 再現可能なチェックと残り

`MEMORA_CHECK_ROOT=<一時出力の実ディレクトリ> bash tools/checks/run-next-generation-checks.sh`
で新規5＋既存10スイートを実コードと隔離fixtureで実行する。外部API、
ユーザーSQLite、実際の音声・写真は使わない。SystemIntegrationChecksは
正常／不正リンク、日付／件数／ID／容量の上限、JSON往復、欠損／破損／
期限切れファイルの拒否。これはWidgetの実機表示やSiri成功の証拠ではない。

残りの優先順:
1. BYOKの実ストリーム／ツール／停止／権限変更／引用とUI操作の承認E2E。
2. project/recordを越えないAgentToolの統合、添付から操作するエージェント経路。
3. 非破壊な識別子移行＋App Group、実機Widget／Siri／Control／録音Island。
4. 既存ライブラリ・Project・JournalのLight/Dark/Dynamic TypeとGlassの
   frame単位の回帰、起動／スクロール／メモリの同条件計測。
5. Gmail/Notion/MCPの実認証E2E、追加サービスのOAuthバックエンド。
6. 永続ジョブ・中断再開・調査分担・日次金額予算とサーバー強制。

未接続機能を利用可能として表示しない。上記を残して全指示の完了とは扱わない。

P3コード最終build: `2026-10-14T13-24-19-71bc316c.log` 成功。
Memora／Widget ExtensionのAppIntents metadataを抽出。既存の非AppIntents
targetの抽出skip警告1件、compile/link errorなし。15スイート成功。
途中のhostチェックにthrowing autoclosureのcompile errorがあり、decodeを
先に行うよう修正して再成功。既存DBや実際の認証サービスは使っていない。

最後の生成UI補正: 参照型全てに現在のワークスペース・保存保護・cloud grant
の再確認を適用。本文のない不正UIは空白にせず理由を表示。途中のJSONは
decodeしない。NativeAIInterfaceChecksで途中／本文なしfallbackも追加検証。

Simulator追加確認: iPhone 18 Pro Maxで、Deep Linkの今日フィルター（メニューの
チェックを確認）、空白Ask AIと入力フォーカス、共有初期OFF／未設定の無効
スイッチ、Dark + accessibility_extra_largeの表／グラフ／timelineを確認。
WidgetKitギャラリーでクイック記録／Ask AI（小・中）／今日（未設定）を確認。
Ask AI小Widgetを一時追加し、実タップで会話とキーボードまで遷移。検証用
Widgetは削除し、既存のMap／Calendar Widgetは維持した。

Project Widgetは初回にplaceholderが残ったため、設定Intentをfile-privateな
Extension専用型からSharedの安定した型へ移し、defaultResultと初期化を追加。
host／Extension両方でmetadataを持つ。
`2026-10-14T13-41-05-367b47d5.log` build成功（既存警告1件）。補正後に
ギャラリーと実ホーム画面のmediumで「情報共有は未設定」を確認し、実タップ
でLibraryのProjectsセグメントへ遷移。検証用のProject Widgetも削除した。
登録変更／既定値の追加を同時に行っているため、原因を片方に断定しない。
optional entityの既定値方針は
[Apple configurable widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)
を参照。共有なしでプロジェクト名や件数の架空値を使わない。

共有設定を伴う実データ表示、プロジェクトのパラメーター選択、ロック画面の
accessory各サイズ、実Siri／録音Intent／Control／Islandは未検証。端末内の
Widget表示・リンク確認を実機確認や共有設定完了の代替にしない。

P5補正: 生成UIの表示用contextをModelで1度に作る。各行で全記録のgrant集合
やメモリ指紋を再計算しない。今回のUIが参照するタスクだけを確認し、出典は
辞書化する。表示を越える権限キャッシュを残さず、操作時は現在の状態を再検証。
通常回答・見た目・承認経路は保持。実機の描画時間は未測定。

## 2026-10-14 — 共通添付抽出と会話の対象範囲

Ask AI／記録の質問の添付は、既存ProjectSourceExtractionを再利用する。
テキスト、PDF、画像の端末内OCRを共通化。画像から読むのは文字だけで、
写真の意味理解・画像の外部送信・音声の直接解析は追加していない。
プロジェクトの添付は従来のソース保存・解析・プライバシー許可の経路を維持。

BoundedTextReaderは通常のローカルファイルだけを最大512KiB＋検出用1byte
で読む。末尾の不正UTF-8を、読み取り上限で切れた文字と誤認して捨てない。
抽出前に50MiB以下、PDF最大20ページ・各12,000文字、画像OCR最大2,000px、
画像PDFのOCR最大3ページを確認。添付本文は最大8,000文字、送信予算は
従来の40%上限。OCR・ページ／文字の省略は既存の補足表示へ渡す。
一時的な会話添付にはプロジェクト用サムネイルを生成しない。

AIAttachmentText.prepareはキャンセルを伝搬するutility処理の外で抽出する
（現在のpriorityはuserInitiated）。requestContentは完成した本文だけを受け、
ファイルを開かない。端末内の短縮再試行でも同じ本文を使い、再解析しない。
prepared本文のID・名前・URLが質問の添付と一致しなければ送らない。
Visionの同期OCRそのものを強制中断する保証はなく、処理境界で確認して結果を破棄する。

AIQueryScopeを本文構築時にも適用し、渡された配列に別の記録が混じっても
除外。記録／プロジェクト質問では他の記録のタスク・未所属タスク・全体の
個人メモリを混ぜない。抽出後、送信直前、ストリーム更新、保存前に現在の
内容・所属・許可・ワークスペース・保存保護を確認し、変更を通信障害とは
区別して停止する。送信済みデータを取り消す機能ではない。

検証: hostの16スイート成功。AttachmentScopeChecksで日本語／絵文字の
途中切断、不正UTF-8、リンク／非ローカル／directory拒否、キャンセル、
記録／プロジェクト／タスクの境界、prepared本文の一致を確認。
Bitrig build `2026-10-14T15-49-48-a9072500.log` 成功、既存metadata警告1件。
iPhone 18 Pro Maxの自己チェック画面でAI shared attachment extraction、
AI context limits、Request scope、Scope isolation、Attachment read limitの
成功を確認。テストPDF・OCR画像・壊れたPDF・音声・50MiB超のfixtureを
使い、ユーザー資料・外部APIは使わない。

未検証: 実ファイルの選択からBYOK回答までのE2E、実機OCR品質とメモリ、
応答中の実権限変更。添付付き依頼は引き続きgrounded回答で、エージェントの
操作経路には統合していない。project/recordの変更ツール統合も未完了。
