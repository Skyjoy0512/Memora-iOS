# 承認・質問の待機とキャンセル

2026-10-16。前回の親子共通予算に続き、ユーザー操作待ちの寿命を監査した。

## 確認した問題と変更

従来のrequestAgentApproval/requestAgentQuestionsはCheckedContinuationをmodelへ直接保存し、Taskの取消だけでは再開しなかった。stopAIChat/startNewAIChat等の明示的resolveがある経路は解放できる一方、子Taskだけをcancelする経路では待機が残る可能性があった。また、停止したTaskが遅れてrequest関数へ入ると、既存の新しいカードを先に辞退させていた。AgentQuestionCardには、回答/閉じる操作を対象request IDに限定する確認もなかった。実環境で不正writeが発生したことを示すものではない。

AgentInteractionWaiter<Value>をMainActor上の一時的な待機所有者として追加した。承認Boolと質問[String]で同じ取消・置換規則を使う。既存のpendingAgentApproval/pendingAgentQuestionsは表示用に保持し、保存形式、権限、モデル設定、ツールregistry、Keychainは変更しない。

- 取消済みTaskはカードを提示せず、現行カードを置換しない。待機中の取消は対応するcontinuationをnilで再開する。
- 各waitに内部tokenを作り、遅れた取消callbackが後継の待機を解放しない。呼出し側が同じ表示IDを再使用しても内部tokenは別になる。
- 回答時は対象IDが現行の待機と一致する場合だけ一度再開する。古いカードの回答/閉じる操作は無視する。stop/new chatの一括終了は既存どおりID指定なしで辞退する。
- 正常な新しい待機が始まった場合は従来どおり以前の待機を辞退する。同時に複数の承認を許可する新しいqueue/包括的grantは作らない。
- 待機前後にTask取消・対象messageの存在・既存cloud provenance認可を確認する。承認ボタンとTask取消が競合したときも、取消済みなら許可を返さない。
- pendingの解除とcontinuationのresumeをMainActorで一度だけ行う。承認済みtask draftの編集内容とdidChangeDataによる再実行防止を維持する。

画面のレイアウト/配色/アニメーション/Glass/FAB/ナビゲーションを変更しない。タブ移動は従来どおり会話を保持し、単にタブから離れたことを停止とは扱わない。新規会話・明示停止・workspace変更の既存取消経路を使う。外部に到達済みのwriteや課金を取消で撤回する保証は追加しない。

## 変更ファイル

| ファイル | 内容 |
|---|---|
| App/AgentInteractionWaiter.swift | 型付き待機、取消handler、ID/token検証、一度だけresume |
| App/MemoraModel.swift | 直接continuationを待機所有者へ置換。stored stateのみ |
| App/MemoraModel+Agent.swift | 承認/質問の登録・解除、前後の取消/認可確認 |
| App/AgentApprovalCard.swift | 回答先approval IDを明示 |
| App/AgentQuestionCard.swift | 送信/閉じる対象request IDを明示 |
| tools/checks/AgentInteractionChecks.swift | 実waiterの隔離Swift 6回帰チェック |
| tools/checks/run-motion-loading-checks.sh | 上記checkを組み込み |

## 検証結果

- `run-motion-loading-checks.sh`: 成功。承認/辞退/質問回答、待機中取消、承認直後取消、待機置換、古いIDの拒否、同一表示IDの後継保護、取消済みTaskの遅延登録、TaskGroup取消、100回の取消と回答の競合を確認。実waiterを使い、取消後のmock writeは0件。新checkはSwift 6 modeでコンパイルする。
- `run-next-generation-checks.sh`: 成功。共通agent loop、registry、privacy/provenance、conversation復元、resident、stream、native UI schema等の既存回帰チェック。
- `bitrig preview -platform iOS`: 修正後のDebugビルド・プレビュー更新に成功。log `2026-10-16T16-48-14-6acff65d.log`。初回の型推論エラーは明示的なValue?型で修正済み。
- `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`: 成功。log `2026-10-16T16-49-24-dce2aeb9.log`。両ビルドは既存Share ExtensionのAppIntents metadata抽出省略の警告1件。logはBitrigの当該project Builds/logs内。
- `git diff --check`: 成功。
- プレビューのiPhone 18 Pro Maxで、Settings → プロトタイプ → 状態と復旧 → タスク候補（承認と保存の検証）を操作。架空の候補を表示後、「やめる」と「検証を停止」でカードが消え、開始ボタンが再び有効になることをAXで確認した。承認待ちのまま戻り、再度開いた際も古いカードがないことを確認。「追加」は押していないため検証タスクの保存は実行していない。検証画面の既存cleanupは自身のmessage IDだけを除去する。

初回checkでSwift 6のregion isolation checkerがTaskGroup内のclosureにコンパイラ診断を出したため、その待機をMainActorの補助関数へ移して同じ取消動作を検証した。取消検証を無効化したり、Swift 6チェックを外したりしていない。

## 未検証・測定範囲

実provider/ネットワーク、Gmail同時承認、承認して実writeするE2E、新規会話/ワークスペース切替中の本番agent UI、実機、VoiceOver操作、実機Releaseの性能・メモリ・実料金は未検証。質問カードの新旧置換は実waiterのhostテストであり、画面操作の検証とは区別する。今回のUI確認は検証画面の停止/辞退/離脱で、全Ask AIシナリオの成功を意味しない。追加サービス・有料呼出し・ユーザー記録やキーのテスト利用はない。
