# 人物とタスクを人物IDで関連付ける

2026-10-17。`11e3d21`からの継続実装。BYOK、RecordAccessPolicy、既存のタブ/FAB/コンポーザーを維持し、外部サービスは呼び出していない。

## 動作

タスク作成・編集のFormに「担当する人物」を追加した。人物を選んだときだけ`TaskRelationships.assigneePersonID`へUUIDを保存する。名前を入力しただけでは人物を確定しない。同じ名前の候補にはメモとIDを添える。短縮IDも重なる場合は完全なIDを表示し、選択値は常に完全なUUIDで扱う。

人物詳細では、人物を指定した担当タスクと「担当名のみ一致・本人未確認」を別々に表示する。名前照合は現在の人物一覧で名前が一意の場合だけで、本人の発言・約束の証明にはしない。同じ会議の別担当タスクは「一緒の会議で残っていること」として扱う。

人物の改名は、人物を指定したタスクの表示名へ反映する。本人が確認した統合は人物IDの関連と会議タグを移す。名前だけの旧タスクの担当表記は変更しない。人物削除後もタスク側の古いIDを保持し、後から登録した同名の別人が引き継がないようにする。編集時には削除済みの人物との関連を表示し、本人が選び直すか解除できる。

`ownedByMe`の明示指定を優先する。人物IDを指定したタスクは、担当名がプロフィール名と同じという理由だけで自分のタスクにはしない。

## 権限と保存

- 人物の追加指定・担当変更・人物統合で担当IDが変わると、タスクの外部送信許可を失効する。個人情報の分類を適用し、元会議がより機微な場合はその分類を保持する。元会議から切り離すときも、分類を下げない。
- `read_person`は人物限定の依頼で、指定されたperson_idと現在の人物スコープを処理前に確認する。会議に紐付かない明示担当タスクも、開始時に固定したtask IDの範囲で読める。
- `read_person`と`list_tasks`は、人物との関連と個別の外部送信可否を別々に検証する。人物との関連だけでは外部AIへ送らない。
- 担当変更・人物削除・会議の人物タグ変更で現在のスコープと一致しなくなった場合、ツール実行と次のクラウド送信を拒否する。Task自体の変更/許可失効は既存のfingerprintとRecordAccessPolicyでも再検証する。
- 改名・統合・削除は関連するSQLite文書を一括保存してから画面へ反映する。保存失敗時は編集画面を閉じない。複数人物の削除では、削除前にIDを固定する。
- 任意フィールドの追加で既存データと互換を保つ。`relationships`が存在しないデータ、`documentIDs`のない旧形式も既定値で読み込む。旧タスクを人物IDへ自動変換するマイグレーションは実施しない。

## 実装ファイル

|領域|ファイル|
|---|---|
|保存モデル・分類・選択候補|`TaskRelationships.swift`、`PersonTaskAssociation.swift`、`PersonSelectionOption.swift`、`TaskOwnership.swift`|
|担当の保存・改名・統合・削除|`MemoraModel+Tasks.swift`、`MemoraModel+People.swift`|
|人物限定Ask AIと再検証|`AIPluginExecutionPolicy.swift`、`MemoraModel+PersonChat.swift`、`MemoraModel+PersonScope.swift`、`MemoraModel+AIProvenance.swift`、`MemoraModel+AutomaticRecordTools.swift`|
|人物ツール|`MemoraModel+PersonTools.swift`へ`readPersonTool`を分離。呼出しは既存`MemoraModel+AgentTools.swift`を維持。`AgentTool.swift`と`MemoraModel+Agent.swift`で担当/約束の区別とperson_idの指定を案内|
|UI|`TaskAssigneeFields.swift`、`AddTaskView.swift`、`TaskEditView.swift`、`PersonMemory.swift`、`PersonDetailView.swift`、`PersonEditSheet.swift`、`PeopleManagerSheet.swift`|
|回帰テスト|`tools/checks/PersonTaskChecks.swift`、`run-person-task-checks.sh`、既存runner/ownership fixtureの更新|

Appのファイルはすべて`App/`配下。プロジェクト設定・新しい依存・サーバーは追加していない。

## 検証

`bash tools/checks/run-person-task-checks.sh`で本番のTask/People/人物スコープ/`read_person`処理と本番のLocalStoreを使用し、隔離した実SQLiteへ保存する。UI・通知・会議/ジャーナルの形状とモデルの保存呼出しを小さなfixtureに置き換える。RecordStoreのキュー自体は既存の別テストが担当する。

確認した内容:

- 同姓・同名、同じ短縮ID、表記揺れと名前だけの旧タスク。
- 明示的な人物ID選択、存在しないIDの拒否、他人の同名タスクの分離。
- 個別送信許可、非公開タスク、別人IDの直接呼出し拒否、担当変更後の許可失効。
- 元会議が機微な場合の、切離しと担当変更による分類保持。
- SQLite triggerで人物/タスク一括保存を途中失敗させ、レコードと画面状態がともに変わらないこと。
- 改名・統合、人物削除、同名での再登録、削除済みIDの保持、ワークスペース不一致、復元中の拒否。
- SQLiteを開き直した後も人物IDを保持すること。
- 500人・2,000タスクの名前照合。ホスト上の測定値であり、実機性能やLLMの回答品質を意味しない。

シミュレーターで、未保存の作成フォームを使い、人物選択→元のFormへの復帰→自分のタスクへの切替による人物指定解除を確認した。ダーク表示と`accessibility_extra_large`での折り返し、AXの操作名/選択値を確認し、文字サイズを戻してキャンセルした。実ユーザーのタスク・人物を追加/更新/統合/削除していない。既存のコンポーザー下書きも維持した。

## 残る範囲

- 実機のVoiceOver音声走査、同名人物の実UI保存/統合、実BYOKを使った一連の会話は未検証。
- 人物メモmetadataには独立した外部送信許可と永続fingerprintがないため、人物ツールを含む過去回答のcloud再利用は引き続き不完全として扱う。
- ジャーナルには人物IDを新設していない。名前の言及を本人の発言として扱わない。
- 議事録やAIの担当名から人物IDを自動確定しない。AIが提案したタスクも、名前だけの場合は未確認のまま保持し、本人が編集画面で人物を選択できる。
- 人物削除は元の会議やタスク本文を削除する操作ではない。元記録に書かれた名前は元記録側で管理する。

ビルド・回帰スクリプトの結果は[検証記録](ASK_AI_NEXT_VALIDATION.json)の`followups`へ記録する。

最終検証: coreのDebugビルドと、説明文を含む最終Releaseプレビューが成功した。
既存のnext-generation/motion-loading/optimization各スクリプト、および人物タスクと
tool-integrationの追加確認が成功した。AppIntents metadataの既存警告1件を除き、
compile/link errorはない。詳細なログ名と検証範囲は機械可読記録に保持している。
