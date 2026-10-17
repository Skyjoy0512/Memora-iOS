# 構造化UIのタスク操作 — 承認と保存

基点 `505bbe0`。タスク完了ボタンからの操作を、呼び出しspyだけでなく本番の承認待機・
タスク更新・SQLite保存まで検証する。モデル/API/実アカウント/ユーザーの記録は使わない。

## 修正

- `completeInterfaceTask` はTaskをキューへ入れた後、実行開始時にもrequest IDと参照権限を照合。
  待機中に新しい会話・復元・保護・workspace変更が入っても、古いUIからdispatchしない。
- `updateTasksTool` は変更前と承認後の両方で、現在のregistry/schema、plugin利用状態、
  person policy、workspace、保護状態、cloud provenanceを確認する。
- 承認時のplugin policyを値として保持し、削除・対象の変更・制限の緩和も含めて差分があれば中止。
  対象taskの内容だけでなく、現在の会議/project範囲、taskごとの許可と親会議の許可も再照合する。
- `update_tasks` のschemaはルート/各更新項目の未定義キーを拒否し、1〜30件を規定する。
  `id`のみの変更なし指定は従来どおり変更しない。期限・担当・タイトル・本文の更新は許可しない。
- 複数taskは従来の単一SQLite文書/transactionで保存し、成功後だけmodelとreminderを更新する。
- `requestAgentApproval` を `MemoraModel+AgentApproval.swift` へ同じ実装のまま移し、hostから
  本番 `AgentInteractionWaiter` と合わせてコンパイルできるようにした。承認UIの意味は変えない。
- plugin policyのEquatable追加は、承認時と保存時の実行範囲比較のため。永続化形式は変更しない。

## 検証経路

```
completeInterfaceTask（本番）
  → fixtureのdispatch入口 / registry組立
  → AIToolRegistry / ToolInputValidator / AIPluginExecutionPolicy（本番）
  → updateTasksTool（本番）
  → requestAgentApproval / AgentInteractionWaiter（本番）
  → fixtureの承認入力
  → persistNow（fixtureのmodel入口）→ LocalStore（本番）
  → 別のLocalStoreで再オープンして保存内容を比較
```

全toolを選ぶperformAgentTool、registryの組立、通知サービス、scope用のmeeting配列はfixture。
実際のSwiftUIカードのタップやOS通知、LLM通信をこのテストで通ったとは報告しない。
既存のtransport/registry/会話/interactionテストと組み合わせて境界を確認する。

## 確認項目

- on-device扱い/cloud扱いの承認成功。承認前はDB/modelとも未変更、保存後は期限・担当・本文を保持。
- 二重タップ、既に完了したtask、別message/未知task ID、別のapproval ID、承認IDの再利用。
- 拒否、承認待ちでのTaskキャンセル、承認解決直後のキャンセル。
- Taskをキューへ入れてからdispatchするまでのgrant取消、workspace・復元・保護・message消失。
- 承認待ちでのplugin無効化、registry無効化、policy削除/変更、task編集/削除、workspace変更、
  復元/保護/保存拒否、message消失、taskのcloud許可取消。
- taskの値を変更せず親会議のcloud許可を取り消した場合。
- project scopeの承認待ちに、親会議をprojectから外した場合。
- 未知・重複task、型の違う完了値、未定義キーを含むbatchを部分実行しない。
- テスト用SQLiteにBEFORE INSERT triggerを作り、保存を実際にABORT。
  全件が元のまま、reminder更新なし。trigger除去後に別の依頼・新しい承認で2件とも保存できる。
- cloudへ渡したtaskを完了にした後も、古い出典fingerprintを勝手に更新しない。
  古いcloud contextは失効する。現状は再依頼が必要であり、権限を再付与するUIは未実装。

## 実行

`bash tools/checks/run-artifact-provenance-checks.sh --interface-task-execution`

`run-next-generation-checks.sh` の最後からも実行する。通常のartifact-provenance検証は従来どおり。
全fixtureは専用の一時ディレクトリ/SQLiteを使い、終了時に除去する。
schema違反のテストにはキャンセル期限を設け、誤って承認待ちに入った場合も永久待機しない。

ビルド・runnerの最終結果は `ASK_AI_2_VALIDATION.json` の `task_execution_followup` を参照。
最終Debug preview / Release simulatorは両方成功、各11件の既存警告。
ログは `2026-10-17T13-19-36-10481206.log` / `2026-10-17T13-19-37-00bd96b0.log`。
新しい実行モード、指定3runner、shell構文、JSON、diffの空白検査は成功。
実機VoiceOver、日本語IME、実providerの停止、実接続A〜E、長い会話/大量データでの実測は未検証。
