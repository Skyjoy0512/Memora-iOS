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
