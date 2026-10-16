# 親・子エージェントの依頼単位予算

2026-10-16。分担調査の子担当は従来、それぞれCloudAgentSessionの16要求/128,000出力tokenの予算を新規作成していた。親の16往復と子2〜3担当×最大6往復は別枠で、同じ依頼から派生する要求をまとめて制限できなかった。また子担当だけが独自loopで、共通loopのcall ID重複検証を通っていなかった。

## 所有と上限

AgentRunBudgetはMainActor上の一時オブジェクト。CloudAgentSessionの初期化時に通常は新規作成し、主担当からdelegate_researchへ同じ参照を明示的に渡す。各子の会話履歴、ツール集合、model selectionは別のまま。予算の共有は権限の付与ではない。モデルのstored state、SQLite、UserDefaults、Keychain形式を変更しない。

- 依頼全体で最大16 model要求、単一要求512KiB、累積要求4MiB、累積response 2MiB。AgentSessionBudgetの既存値を同じownerで使う。
- 最初のmodel要求から600秒を共有。子担当を後から作っても時計をリセットしない。model/tool境界で協調的に確認する。進行中の全network/外部操作を厳密な時刻でkillする保証ではない。
- 生成量は確認済みprovider/modelだけ最大128,000 output tokensを共有。1要求は最大32,000、残量が少なければその範囲にする。その他のprovider/独自endpointへの新しいfield追加はしない。詳細は[生成予算](AGENT_GENERATION_BUDGET.md)。
- 実tool呼出し24回は従来のmessageID単位のカウンターを親・子が継続して共有する。子は各最大6往復、1turn最大4call、読み取り専用で再委譲できない。
- 独立した質問、project/record質問、resident jobはそれぞれ新規owner。全利用者/月次/独立jobを横断する料金上限ではない。

## 並列予約と精算

AgentOutputBudgetの単一pending予約を、UUIDと要求上限を持つ予約票へ変更した。並列要求の開始時点で全予約を加算し、応答が順不同でも自分の予約だけを精算する。別ownerの票、上限を書き換えた票、二重精算は拒否し、charged counterを減らさない。usage欠落/不正/失敗時は予約を保持する。報告値が要求上限を超えれば共有ownerを停止し、その応答からtoolを実行しない。

予約だけで128,000を使っていても、進行中の応答が有効なusageを返せば未使用分が戻る。この場合は新しい予約を拒否しても、既に開始した兄弟を全停止しない。予約が取れなかった担当は未完了として返し、自動再開/課金再試行/無制限待機はしない。全予約が精算済みで予算を使い切った場合や、要求数/byte/時間の上限に達した場合はownerを停止する。

## 実行と停止

子担当をAgentConversationLoopへ移した。各model前後・tool前後に共有ownerを確認し、遅れて返った応答からtoolを実行したり完了回答を受理したりしない。call IDの再利用、batch内の重複、空ID、call件数、各turn/実行時間の既存検証も子へ適用する。子のloop上限は型付きのexecutionLimit失敗として返す。未完了かどうかをモデルの本文の文字列で推測しない。主担当等の従来の上限メッセージはdefault動作のまま。

主担当の終了時にownerをcancelする。子はstructured TaskGroup内で実行し、親Taskの取消が伝播する。共有ownerが停止した子の報告を受け取ったら兄弟をcancelAllし、同じmessageIDで承認待ちのカードだけを辞退してcontinuationを解く。新しい依頼のカードは触らない。ユーザー承認待ちをLoadingとして扱わない。送信済みの要求や完了した外部writeは取消で撤回できず、自動rollback/再実行もしない。

分担開始の既存承認、追加BYOK料金の説明、2〜3担当のassignment検証、同じscope/requestID/workspace/provenanceの実行時確認を維持する。子へ提示するtoolも現在のenabledAgentToolsと明示的plugin policyで絞る。許可された読取toolがなければ追加model要求を始めない。Gmailの費用確認やMCP/書き込みの承認を予算共有で省略しない。

## 変更ファイル

| ファイル | 役割 |
|---|---|
| App/AgentRunBudget.swift | 依頼の共有owner、回数/byte/時間/output/取消 |
| App/AgentOutputBudget.swift | 並列の予約票、順不同の精算、二重/別owner票拒否 |
| App/CloudAgentSession.swift | ownerの注入、実送信前とtool変換前の共通確認 |
| App/AgentConversationLoop.swift | 実行境界の共有check、子の型付き上限失敗 |
| App/MemoraModel+Agent.swift | 主担当のownerを子へ渡し、終了時に閉じる |
| App/MemoraModel+AgentResearch.swift | 同じowner/共通loop、既存承認/読取scope、停止時の兄弟/承認待ち解放 |
| tools/checks/AgentGenerationChecks.swift | 既存生成チェックを予約票APIへ更新 |
| tools/checks/AgentRunBudgetChecks.swift | 共有/並列/取消/遅延/上限の隔離回帰 |
| tools/checks/run-motion-loading-checks.sh | shared runチェックを追加 |

## 検証

AgentRunBudgetChecksは主担当+子3担当のmock Swift Taskで16要求を共有し、17回目がdispatchされないことを確認する。並列output予約、順不同refund、二重/別owner/改変票、128,000超の予約拒否、firm exhaustionと一時的な予約競合の区別、共有byte上限、virtual clockの599/600秒、別依頼の独立性を検証する。実AgentConversationLoopに遅延mock応答を返し、取消後はtool/acceptが0件になること、tool途中の取消で後続を実行しないこと、子の上限を完成回答として扱わないことも確認する。

実API、キー、ユーザー記録は使用しない。実provider E2E、承認カードの画面操作、Gmail同時承認、実機のメモリ/所要時間/料金は未検証。App側の回数・生成量の有限予算であり、入力token/請求金額/サーバー課金の強制予算は別の課題。

### 今回の実行結果

- `bash tools/checks/run-motion-loading-checks.sh`: 成功。既存のmotion/loading/streaming/生成量チェックに加え、今回のAgentRunBudgetChecksを実行。
- `bash tools/checks/run-next-generation-checks.sh`: 成功。共通loop、registry、権限、会話復元、resident等の既存回帰チェック。
- `bitrig preview -platform iOS`: Debugビルド成功、プレビューを更新。log: `2026-10-16T16-04-17-756b3dd5.log`。
- `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`: 成功。log: `2026-10-16T16-04-19-82051fcf.log`。
- `git diff --check`: 成功。

ビルドlogはBitrigの当該project Builds/logs内。両ビルドの警告は既存Share ExtensionのAppIntents metadata抽出省略1件。実機Releaseの性能計測、画面上での承認/停止操作、実providerとの通信を行った結果ではない。今回の数値は設定上限と合成テストの結果であり、性能改善率や実料金削減率は未測定。
