# Agentの生成トークンとusage境界

2026-10-16。CloudAgentSessionの既存BYOK経路を段階的に強化する。金額の請求処理、認証、保存形式、画面配置を変更しない。

## 対象と設定

| 接続/モデル | 要求フィールド | 1要求の出力上限 | セッション予約上限 |
|---|---|---:|---:|
| Anthropic直結、既存の登録モデル | max_tokens（既存） | 32,000 | 128,000 |
| OpenAI直結、gpt-6-sol / gpt-6-luna / gpt-6-astra | max_completion_tokens | 32,000 | 128,000 |
| DeepSeek直結、deepseek-flash / deepseek-v4-pro | max_tokens | 32,000 | 128,000 |
| その他のモデル/プロバイダー、独自endpoint、独自credential | 新しいtoken fieldを追加しない | 従来どおり | 既存の要求数/時間/byte上限のみ |

モデルIDの完全一致で適用する。推測したprefix、未確認のAPI、Memora Intelligenceへ新しいfieldを一律追加しない。Anthropicの既存32,000上限を基準とし、長いdocumentをtool引数で返す余地を保ちつつ、有限の生成量にする。複雑な推論/長文が上限へ達した場合は未完了として停止する。自動で上限を上げたり、有料要求を再送したりしない。

予約上限は1つのCloudAgentSession内の生成量。全質問の月次上限、subagent間の共有上限、入力token上限、ドル料金上限ではない。Provider側が要求上限とusage契約を守ることを前提とする。独自サーバーが上限を無視する場合の金額をクライアントだけで保証できない。BYOKは利用者のキーを既存経路だけで使い、運営サーバーへの送信を追加しない。

## 送信前と応答後

AgentOutputBudgetは送信前に最大32,000を予約し、残りが小さければ要求値も小さくする。完了応答の有効なoutput countが得られた場合だけ、予約の未使用分を戻す。usageが欠落、不正、途中のカウンターしかない場合は予約全量を保持する。例えばusageなしの32,000予約が4回続けば、5回目はネットワークへdispatchする前に止まる。有効なusageが毎回1,000なら、既存の16要求を生成予算だけでは妨げない。16要求・24tool・600秒・既存byte上限は別途維持する。

同時に重ねた予約、2回の精算、負数、上限超過、整数overflowを避ける。要求が失敗/中断した場合は予約を戻さず、そのセッションから自動再開しない。報告されたoutputが要求上限を超えた場合は、その応答のtoolを渡す前に停止し、次の予約も拒否する。既に完了した承認済み操作をrollbackしたり自動で再実行したりしない。

## Streaming usage

- OpenAI対象モデルはstream時だけstream_options.include_usageを要求する。choicesが空の最終usage chunkを受理し、最終応答のtop-level usageへ保持する。非stream時にはstream専用オプションを送らない。
- DeepSeekは現在の公式契約で最終content chunkにusageがあるため、追加オプションなしで保持する。
- Anthropicのmessage_startのinput/cache情報を保持し、初期output counterは精算に使わない。stop_reasonを伴うmessage_deltaの最終usageで更新する。累積値を加算しない。最終output countがなければ予約を戻さない。
- completion_tokens / output_tokensはreasoning等の詳細の合計を既に含むため、詳細を二重加算しない。bool、文字列、負数、非整数、無限大/表現不能値を有効なcountとしない。
- usageはprovider履歴のassistant messageへ混入させず、本文やUI表示も変えない。token上限による正常な打切りは通信切断と区別してexecutionLimitで報告し、未完了のtool JSONを実行しない。

## Sol/LunaのChat Completions互換性

公式資料でこの2モデルのChat Completions function callingはreasoning_effort=noneが必要とされる。AgentGenerationPolicyが、直結・完全一致のSol/Luna・空でないtoolsという条件でのみnoneを設定する。モデルを置き換えず、Astraやtoolなし要求へ広げない。Responses APIへの大規模移行は今回行わない。CloudAIServiceを使う要約/通常completion経路にはこの変更を加えない。

## 検証と限界

AgentGenerationChecksは実際のpolicy、usage decoder、予約budgetを合成データで検証する。実AgentConversationLoopと組み合わせ、usage不明時の5回目のdispatchが起きないこと、要求上限違反の応答からtool実行が起きないことを確認する。CloudStreamChecksでusage-only chunk、null usage、Anthropicの累積/初期/欠落usageを検証する。実API/キー/ユーザー記録を使わない。

残課題は、他provider/モデルへの契約確認と適用拡大、正確な入力tokenの送信前見積り、provider usage/priceに基づく金額予算、subagentを含むrun全体の共有予算。Memora Intelligence運用時には、認証されたserver側で予算を強制する必要があり、本変更をその代わりにしない。実provider E2E、課金額、実機性能は未検証。

## 変更ファイル

| ファイル | 役割 |
|---|---|
| App/AgentGenerationPolicy.swift | 確認済みモデル別field、stream usage、Sol/Luna tool互換性 |
| App/AgentOutputBudget.swift | 予約/精算/残量/異常応答での停止 |
| App/CloudTokenUsage.swift | 非負整数のoutput countを安全に読む |
| App/CloudAgentSession.swift | 実送信前の予約とtool変換前の精算 |
| App/CloudStreamAccumulator.swift | 最終usageを保持、累積値と初期値を区別 |
| App/CloudAgentTurnDecoder.swift | 上限打切りをexecutionLimitとして区別 |
| tools/checks/AgentGenerationChecks.swift | policy/budget/usage/実loopの隔離検証 |
| tools/checks/CloudStreamChecks.swift | provider stream usageと打切り理由の回帰 |
| tools/checks/run-motion-loading-checks.sh | generation検証の実行 |

## 公式資料（2026-10-16確認）

- [OpenAI Chat Completions: max_completion_tokens / stream_options](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)
- [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol)、[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna)、[GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra)
- [DeepSeek Chat Completions: max_tokensと最終chunkのusage](https://api-docs.deepseek.com/api/create-chat-completion/)
- [Anthropic streaming: message_deltaの累積usage](https://platform.claude.com/docs/en/build-with-claude/streaming)


## 今回の確認結果

- 成功: `bash tools/checks/run-motion-loading-checks.sh`全件（追加のAgentGenerationChecksを含む）、`bash tools/checks/run-next-generation-checks.sh`全件（usage/中断/権限/保存互換性の既存チェックを含む）、`git diff --check`。
- 成功: 最終Debug `bitrig preview -platform iOS`、ログ`2026-10-16T14-02-59-3171262a.log`、iOS 27.1 SDK / iOS 18 deployment target。Share ExtensionのAppIntents.framework非依存に伴うmetadata extraction警告1件、コンパイルエラーなし。
- 未検証: 本変更に対する実機/UIの詳細回帰、実provider E2E、課金額、追加の性能比較。テストに使ったデータは架空のusage・モデル設定・mock tool結果だけであり、実キー/個人記録を使わない。UI変更はなく、既存のLiquid Glass/コンポーザー/NavigationStackを維持する。
- 成功: 最終Release `bitrig build -destination generic/platform=iOS Simulator -configuration Release`、ログ`2026-10-16T14-04-10-a1e5d8f3.log`、result success。同じShare Extensionのmetadata extraction警告1件、コンパイルエラーなし。実機Release計測とは区別する。
- 実装コミット: `c6aa157`。外部サービスの契約・本番デプロイ・実料金の発生を伴うAPIテストは行っていない。
