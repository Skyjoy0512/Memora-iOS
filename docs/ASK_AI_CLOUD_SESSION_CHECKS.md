# Ask AI 通信モック統合検証

## 対象

GitHubの `main` へ `af3007c..13af297` の20コミットを通常のfast-forward pushで反映した後の継続作業。
本番 `CloudAgentSession` のHTTP送信形式から会話ループ・人物参照・メール下書き保存までを、
外部へ通信しない `URLProtocol` でつなげて検証する。UIや保存スキーマは変更しない。

`CloudAgentSession` と `CloudTurnStreaming` に内部の `URLSessionConfiguration` 注入点を追加した。
通常の呼出しは引き続きephemeral session、600秒のresource timeout、既存のKeychain取得とBYOK、
送受信上限、ストリーミング解析、完全なturnの検証を使う。セッションごとの設定をコピーし、
各リクエストの終了時には従来どおりsessionを無効化する。
テスト用コードと架空キーは `tools/checks/` のみにあり、アプリに組み込まない。

## 検証する境界

`bash tools/checks/run-cloud-session-checks.sh` は本番Swiftファイルをhostでコンパイルする。
すべてのURLを専用の `URLProtocol` で捕捉する。応答scriptが尽きたらエラーにし、
通常のネットワークへフォールバックしない。Keychain/Gmail/credit表示はfixtureであり、
実際の認証情報・OAuth・ユーザーの記録は使用しない。

- OpenAI互換とAnthropicの両形式、それぞれJSONとSSEで人物→下書き→最終回答を処理。
- 実際のPOST URL、認証header、モデル生成パラメータ、選択したtool schemaのみを検査。
- SSEは7byteずつ配送し、日本語を含むJSONと分割されたtool argumentsを復元。
- 次の送信にtool call IDと結果を正しい形式・順序で保持。Anthropicのthinking signatureと
  OpenAI互換のreasoning追加fieldも保持する。
- 同名人物を明示IDで識別。別人のメモ・非公開会議本文が次のモデル送信に含まれないことを確認。
- 実際の `AIToolRegistry` / `AIPluginExecutionPolicy` が未選択tool、不正schema、未接続Gmailを拒否。
- 本番 `read_person` / `draft_email` / document builderと保存処理を使用。
  メールの宛先空欄・下書き状態・内部マーカー除去と、資料の型付きリンク/出典をSQLite再読込で確認。
- 本番の下書き保存をfixture承認で一度停止し、拒否、registry無効化、選択policy解除、
  workspace変更、出典編集、保存失敗で下書きを作らないことを確認する。
  通信が継続可能な場合は拒否結果をモデルへ返し、Anthropicのis_errorも検査。
- モデル応答待ちで人物許可失効・人物メモ編集・削除・workspace変更・復元開始が起きたら、
  応答を採用せず、tool実行と次のモデル送信を止める。
- 未終端SSE、長さ制限で途切れたJSON tool call、前turnのcall IDの再利用を拒否。
- SSE要求に対してJSON応答が返った場合も同じ1回のリクエストで処理し、再送しない。
- 401/402/403/404/429/503とtimeout/切断を本番の失敗理由へ変換し、自動再送しない。
- 使用token数不明の応答は予約を返金せず、4回で128,000のローカルtoken予算を使い切り、
  5回目を送信しない。これはproviderの正確な請求額上限ではない。
- 通信中のTaskキャンセルでは本文を発行せず、応答やツール操作を採用しない。

## 本番コードとfixtureの区分

本番: CloudAgentSession、CloudAIServiceのHTTP失敗判定、URLSession受信、SSE framing/accumulator、
turn decoder、生成/run budget、AgentToolのschema、registry/policy、AgentConversationLoop、
人物/タスク/メモの権限と出典、下書き/資料保存、SQLite。

fixture: Keychain/Gmailの接続状態、credit表示、modelの返答、承認UIとその応答、
MemoraModelの保持状態・通知/メディアなどの依存、registryの組み立てとdispatch入口。
`pluginCallIsPermitted` のfixtureは本番registry/policyを呼ぶが、本番のplugin catalogや
Gmail/MCPの接続/費用承認の全経路を通したとは扱わない。
資料保存は最終回答を本番builderで変換して明示保存する。`create_document` toolやOffice出力を
同じ通信シナリオで実行したことにはしない。人物詳細からのread-only Ask AIとも区別する。

## A〜Eとの対応と残件

| シナリオ | 今回追加した証拠 | 残る統合検証 |
| --- | --- | --- |
| A 人物→会社提案書 | 明示人物ID、個別許可、tool結果の送信、型付き資料のSQLite保存 | 会社テンプレート選択から文書tool/Office実ファイルまでの通し検証 |
| B 過去会話→未完了確認 | 通信履歴のtool結果・追加field維持、失効時停止 | episode検索/現task照合を含む通信シナリオ |
| C Research→PPTX | 共通通信と生成予算、途切れた呼出しの拒否 | 検索transport/反復Research/引用/会社PPTX生成の通し検証 |
| D 会議→メール | 人物に関連するtask/メモから下書き保存、承認後の再検証 | 会議選定/決定事項/参加者を含む完全シナリオ |
| E @選択だけ | 実registry/policyによる不正schema/範囲外/未接続拒否、承認中の無効化 | 実composer選択→catalog→Gmail取得承認→会社書式までの全経路 |

外部サービスの実接続E2E、実OAuth/Gmail Drafts、本文の主張と根拠の意味的一致、
実機VoiceOver/大量データ/消費電力、OSからの出典URL起動、複雑なOfficeの描画は未検証。
新規サーバー・有料API・外部契約・本番デプロイ・実メール送信は行っていない。

## 実行結果

最終結果は `ASK_AI_NEXT_VALIDATION.json` の `cloud_session_transport` に記録する。

実装コミット: `7510099`。

- Debug preview成功: `2026-10-17T12-19-23-5ce30877.log`。
- Release simulatorビルド成功: `2026-10-17T12-19-23-accd0090.log`。
- 両ビルドとも既存のAppIntents metadata extraction skipped警告1件のみ。コンパイル/リンクエラーなし。
- `run-cloud-session-checks.sh` のfocused検証と、追加runnerを含む指定の
  `run-next-generation-checks.sh` / `run-motion-loading-checks.sh` /
  `run-optimization-checks.py` がすべて成功。`git diff --check` / JSON検証も成功。
- UI変更なし。previewのビルド/起動を実施したが、今回の実機/画面操作検証は追加していない。
- GitHub mainは `git ls-remote` でも `13af297bb9e5f0f8257fce3125bee894750f0571` を確認。
  今回の継続作業はこの公開済み地点の後のコミットとして区別する。
