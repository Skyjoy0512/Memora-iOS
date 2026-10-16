# Native Agent Harness 評価

2026-10-16。Memora基準main `5dc9774`。DeepSeek公式masterの確認revision `86a402200d95fecef4529d969836f1fe13c6cb0d`（2026-10-15）。コードの移植・npm依存追加なし。以下は設計比較と今回の限定的な実装判断。

## 一次資料

- [README / developer preview](https://github.com/deepseek-ai/deepseek-harness/tree/86a402200d95fecef4529d969836f1fe13c6cb0d)
- [公式ドキュメント](https://deepseek-harness.github.io/deepseek-harness/)、[architecture](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/docs/architecture.md)
- [Tools](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/docs/subsystems/tools.md)、[Scope](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/docs/subsystems/scope.md)、[Agent loop](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/packages/core/agent-loop/README.md)
- [SAFETY](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/SAFETY.md)、[MIT LICENSE](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/LICENSE)、[THIRD_PARTY_NOTICES.md](https://github.com/deepseek-ai/deepseek-harness/blob/86a402200d95fecef4529d969836f1fe13c6cb0d/THIRD_PARTY_NOTICES.md)

公式は開発プレビュー・互換性破壊あり、セキュリティ監査済み/本番利用向けとは扱わないと明示。sandbox/approvalも隔離の保証ではない。Memoraの外部データ・生成コードへ権限を与える根拠にはしない。

MITはコード利用時の著作権/許諾表示を要求し保証を提供しない。third-party noticesはMIT以外も含み、依存全体を一括MITとして扱えない。今回コードや依存を取り込まず、独自のSwift実装で設計上の責務分離だけを参考にした。将来コードを配布する場合は該当revisionの依存・vendored/payloadライセンスを再評価する。

## 機能比較

| 機能 | Harnessの方式 | 現行Memora | 不足 | 再利用する発想 / 移植可能性 | 技術リスク | 運営コスト | 推奨 |
|---|---|---|---|---|---|---|---|
| Model | LLM adapter seam | LLMSelection/CloudAgentSession、BYOK、on-device | providerごとのusageを揃えた金額予算 | adapterの境界。高、既に同等 | provider API差・token仕様 | BYOKは利用者負担 | 既存を保持 |
| Tool | scoped registry、schemaと実行pipeline | AIToolRegistry、AgentTool、ToolInputValidator | 外部toolの統一output schema | 発見→検証→認可→実行の順序。高 | 外部結果の未信頼性 | 不明/有料readは既存承認 | 既存に有界な実行を追加 |
| Plugin/Cordis | service登録とscopeに連動するdispose | IntegrationCatalog、AIPlugin、IntegrationProvider、MCPClient | 汎用依存graph/共通version契約 | 生存期間・解除時の失効。中 | 動的コードはiOSへ不可、実行途中の解除 | 接続先ごと | native定義と実行時再確認を維持 |
| Discovery | registryからmodel schemaを組立 | SemanticToolDiscovery（端末内、最大16件/24KiB） | 関連性の継続評価 | 関係あるschemaだけ提供。高、既存 | 関連候補欠落 | 追加LLMなし | 現行を再利用 |
| Skills | pluginで再利用可能な手順 | MemoraSkill、Markdown import、宣言tool/permissions | 手順のバージョン・実行評価 | 手順と能力を分離。高 | prompt injection、権限昇格 | 手順選択自体はlocal | 選択だけで権限を付与しない |
| Context | agentごとのscope登録 | ProjectContextBuilder、RecordAccessPolicy、AIQueryScope、添付上限 | すべてのcontextを一律契約にする必要はない | exact scopeと寿命を束ねる。高 | 他project/workspace混入 | ローカル検索は追加課金なし | 実行前再検証を保持 |
| Session | append-only durable eventとlive eventの分離 | AIConversationSnapshot、SQLite、provenance、draft/history | 任意位置のscroll復元、完全なevent replay | transient streamとsettled保存を分離。高、既存 | 危険な中断操作の再開 | 端末容量 | codec互換を維持、write grantは復元しない |
| Loop/limits | model→tool→result、協調取消 | AgentConversationLoop（16往復/24操作）、project6/8、record3/3 | 累積bytes/時間の上限 | 共通予算と境界検証。高 | timeoutでも完了済みwriteは撤回不可 | API要求数は料金と同義でない | 今回の主な強化対象 |
| Events/observability | durable sessionとagent/capability live events | AgentStep、stage、PerformanceLog | 内容を含まない共通のrun観測 | 実際の要求/実行/終了から発火。高 | 診断への個人情報混入 | 既存bounded log | metadataだけ追加 |
| Approval/sandbox | hooks/policy、hostの制約 | AgentApprovalCard、cost確認、MCP endpoint/fingerprint/accountの実行時確認 | OS外サーバーの隔離は対象外 | pipelineで再検証。高 | approvalを信頼境界の代用にできない | 外部read料金未確認は拒否/承認 | 既存を必須経路に保持 |
| Subagents/workflow | scope所有のagent handle | delegateResearch、ResidentAgent（BYOK/read-only） | 汎用workflow editorはない | 独立処理の予算と取消所有。中 | 回数/送信範囲の増大 | モデル要求が増える | 拡張/自動有効化しない |
| Presentation | Web UI/native presentation intents | NativeAIInterface、schema・参照/操作承認 | 機能追加の必要性は未確認 | renderは実行と分離。高、既存 | 不完全JSON/任意リンク | 端末内描画 | SwiftUIと現行schemaを維持 |

## A / B / Cの比較

| 観点 | A: native設計を強化（採用） | B: 利用者管理の外部Harness | C: 運営者のHarnessサーバー |
|---|---|---|---|
| 機能/拡張 | iOSの既存機能を段階追加 | 長時間処理・外部ツールへ拡張可能 | 中央でworkflow/agentを運用可能 |
| 工数/既存影響 | 小〜中、既存境界の改善 | 中〜大、remote protocol/session/authの別実装 | 大、tenant/課金/運用/監視/データ処理 |
| 性能/iOS | native描画・ローカル索引 | network往復、端末外で重処理 | network往復、運営側で容量管理 |
| 安全/認証 | Keychain・既存scope/承認 | 接続認証、最小権限、端末外データ持出し同意が必要 | tenant隔離、機密管理、削除契約、監査が必要 |
| 費用/赤字 | 新サービスなし、BYOK優先 | 利用者のhost/API費用、アプリ側は別課金しない設計 | 固定infra + AI従量費。強制予算なしでは赤字リスク |
| App Store | 現行SwiftUI/審査済み機能、任意code取得なし | remote UIはnative/schemaに限定、審査時の説明が必要 | 同左、追加のprivacy/運営責任 |
| 互換性/保守 | 保存codecとUIを維持 | 開発previewのprotocol破壊にadapterで追従 | serverとapp両方の移行・停止計画 |
| 判断 | 重複を作らず不足だけ実装 | 具体的なユーザー価値を確認して別PoC | 現時点では必要性と採算を確認できない |

B/Cに固有の必要性がないため直接連携PoCは実施しない。Node実行・外部plugin導入・サーバー作成・credential送信・有料AI呼出しは行わない。将来は架空データ・mock API・隔離環境でBの価値と認証/取消/無効化/承認を確認してから再判断する。

## 今回のSwift強化

- AgentSessionBudget: 1 cloud sessionで最大16要求、1要求512KiB、累積要求4MiB、累積response 2MiB、最初の要求から600秒。global/project/record/resident/researchが使うCloudAgentSessionでprovider呼出しの前と結果を扱う前に確認。非stream JSONも受信中に2MiBで停止し、ephemeral URLSessionを終了時に破棄。
- AgentConversationLoop: 既存の往復/操作/ID重複検証に加え、モデル/ツールへの境界で600秒（小さく設定可能）の時間を確認。期限切れのモデル結果からtoolを実行しない。実行中の承認済みwriteをtimeoutで再試行・rollbackしない。
- AgentRunEvent: model要求・tool開始/終了・run終了の事実だけを通知。global/project/recordのrun終了で既存PerformanceLogへ所要時間とtool件数を1件記録。prompt、引数、本文、記録名、キーを含めない。SQLiteの会話形式を変更しない。
- 既存のread/cost/write approval、registryのavailability/schema/provider照合、MCP fingerprint/account/endpoint照合、on-device制限、個人/チーム分離を保持。pluginの無効化は実行時に再確認される。Skillは権限ではない。

これらはローカルの有限予算であり、正確なtoken数やドル料金の強制上限ではない。Anthropicの既存max_tokens、streamの2MiB上限を保持。OpenAI-compatibleの全modelに新しい共通token fieldを無条件に追加しない（provider互換性を損なうため）。Providerごとのusage/price契約と送信前token見積り、ユーザー側API予算が次の課題。Memora Intelligenceの運営側予算強制は未実装backendで必須で、今回接続しない。

時間制限は協調的な境界検証。URLSessionの1要求600秒と併用するが、すべてのtool/ユーザー承認待ちを強制killするdeadlineではない。承認済みで外部へ到達したwriteを取消で撤回できるとは表示しない。終了後に危険な操作を自動再開しない。


## 追加監査: provider応答を実行可能なturnへ変換する境界

2026-10-16。`CloudAgentSession`は従来、OpenAI-compatibleの欠落/不正なarguments、Anthropicの非object inputを空の辞書へ置き換え、壊れたcallをcompactMapで落としていた。JSON fallbackおよび非stream応答では完了理由の検査もstreamより弱かった。`f49af21`の実際のCloudStreamAccumulatorに、終了済みだがinputが文字列の合成Anthropic応答を渡すと受理された。同じ応答は今回のコードで拒否される（ホストSwift、一時ファイル、ネットワーク/キーなし）。既存の権限/承認を回避できたと実証したものではなく、その前段の不正入力受理を修正した。

`CloudAgentTurnDecoder`が両providerの共通境界となる。正常な完了理由、全callの一意で空でないID/名前、object引数、最大24件を検査する。OpenAIのargumentsはJSON文字列のobjectでなければ拒否し、欠落を`{}`へ補完しない。Anthropicもinputをobjectに限定する。正常な空objectは許可する。toolを示す完了理由と実際のcallの有無が矛盾する場合、拒否/打切り/不明な完了理由、deprecated function_callは実行へ渡さない。応答全体が有効な場合だけprovider履歴へ追加する。streamにも同じ検証を適用し、JSON fallback/nonstreamと差をなくした。正常なprovider固有のreasoning/signatureは保持する。

判断根拠は[OpenAI Chat Completionsのfinish_reason](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[Anthropicのstop_reason](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)、[部分的なtool引数の扱い](https://platform.claude.com/docs/en/docs/agents-and-tools/tool-use/fine-grained-tool-streaming)。打切り後に追加LLM要求を自動実行する方式は採用していない。互換APIでも完了理由や標準のfunction形式がない応答は失敗として扱うため、独自形式のみを返すサーバーは別途adapter対応が必要。

`CloudAgentTurnChecks`は通常JSON相当の辞書を実decoderへ入力し、壊れた/欠落した引数、非object、重複/欠落/過長ID、完了理由、件数、正常な空objectを検証する。実際のAgentConversationLoopと組み合わせたmockでは、2件目が不正なら1件目を含めtool実行0件、accept0件、model要求1件で終了する。`CloudStreamChecks`にも不正Anthropic inputと途切れたinput_json_deltaを追加した。schema適合性/availability/cost/scopeは引き続き既存registry/実行時policyが確認する。モデル要求数・BYOK・Keychain・承認・保存codecを変更しない。有料の実provider E2Eは未検証。


## 生成予算の段階的追加（2026-10-16）

CloudAgentSessionへ確認済みモデル限定の送信前output予約を追加した。対象、使用量の保持、互換性、検証、非対象と残る金額/入力tokenの予算は[AGENT_GENERATION_BUDGET.md](AGENT_GENERATION_BUDGET.md)参照。既存のbyte/request/time guardを置き換えず、未確認APIへ同じfieldを押し付けない。


## 親子の予算とscope所有（2026-10-16追加）

[AGENT_RUN_BUDGET.md](AGENT_RUN_BUDGET.md)に、依頼単位の共有予算とstructured child lifecycleを実装した。既存AgentSessionBudget/AgentOutputBudget/AgentConversationLoopを再利用し、child作成で上限がリセットされる経路を閉じる。新しい外部Harness、Node依存、任意code、サービス契約を追加せず、承認と権限は既存gatewayで再確認する。

この追加以降、上記「1 cloud session」の回数/byte/時間予算と生成予算は、主担当とその分担調査の子担当をまとめた依頼単位で共有する。独立した質問やresident jobを横断する金額予算は引き続き別課題。

## 操作待ちの寿命（2026-10-16追加）

[AGENT_INTERACTION_LIFECYCLE.md](AGENT_INTERACTION_LIFECYCLE.md)に、承認/質問の取消・後継保護を記録した。Task取消がcontinuationを確実に解放し、古いカードの回答が現行待機へ渡らないようにした。既存のnative承認カード、registry、cost/scope検証を保持する。新しい外部サービスや包括的権限は追加しない。
