# ワークスペース切り替えと古いAI応答の無効化

2026-10-16。承認/質問待機の改善に続き、会話・参照範囲の切り替えを監査した。

## 監査結果

グローバルAsk AIはaiChatRequestIDを持ち、新規会話/停止/ワークスペース切り替えでTask取消とrequest ID失効を行っていた。この仕組みと会話snapshotの保存・復元を維持する。

一方、プロジェクトチャットはworkspace IDの比較が中心で、切り替え時にjobを取り消していなかった。A → B → Aと戻る間に非同期read/modelが停止していると、戻ったworkspace IDだけでは古い実行を判定できない。またcancelProjectChatは旧Taskが終了するまでbusyを保持していた。旧Taskの無条件deferでbusy/stage/partial/jobを消す実装のまま即時再送だけを可能にすると、新しい実行状態を旧Taskが消してしまう。

これは現行コードの実行所有の不足を示すもので、実ユーザーのデータが外部送信された、または不正writeされたことを実証したものではない。

## 実装

- MemoraModelに一時的なaiWorkspaceGenerationとprojectChatRequestIDsを追加。SQLite、UserDefaults、バックアップ、会話codecへ保存しない。
- didChangeConversationWorkspaceの先頭で世代を更新し、現在のproject chat jobsを取り消す。conversationPersistenceReadyがfalseでも世代の失効を行う。通常のタブ/プロジェクト閲覧の切り替えでは世代を変えず、会話を保持する。
- プロジェクトchatの本文取得、履歴確認、model呼出し、stream本文/stage更新、最終保存の各境界で、現在の依頼ID・世代・workspace・project/thread所属・Task取消・保存先状態を確認。非同期の根拠確認後にも再確認する。従来の資料権限/内容検証を置き換えない。
- 明示停止時はjobをcancelし、該当ownerのbusy/stage/partial/jobだけを直ちに解除。pending messageを停止済みにする。保存済みmessagesは保持する。利用者が明示的に再送した場合、新しいownerで開始できる。
- Task終了時のcleanupと失敗保存は依頼IDが現ownerと一致する場合に限定。遅れた取消Taskが新しい本文・stage・busy・jobを消さない。チャット削除時も該当ownerを解除し、遅い結果から再作成しない。
- 記録/範囲指定のanswerとproject agentにも世代検証を追加。stage callbackも取消/旧世代を除外。AIQuestionViewは送信時の世代を捕捉し、開始前・callback・履歴保存前に確認する。変わっていれば今回の部分回答と引用を外し、contextChangedを表示する。過去の完了回答を一律に消す挙動は追加しない。
- グローバルgrounded pathはTask開始時にもrequest ID/取消を確認し、古いcontext callbackを拒否する。新規会話/停止時の既存ID失効、承認辞退、危険操作を自動再開しないルールを保持する。

世代はworkspaceの寿命確認であり、権限を与えるものではない。BYOK、追加有料要求の既存確認、RecordAccessPolicy、plugin/skill/MCP設定、NativeAIInterfaceの承認、モデル呼出し予算は変更しない。外部に送信済みの処理や課金を巻き戻す保証はない。Node、外部Harness、サーバー、依存関係は追加しない。

## 変更ファイル

| ファイル | 内容 |
|---|---|
| App/MemoraModel.swift | 世代/依頼ownerのstored state |
| App/MemoraModel+ProjectChatExecution.swift | 有効性、限定cleanup、停止、workspace世代失効 |
| App/MemoraModel+ProjectChat.swift | 実送信・callback・保存でowner確認、削除時の解放 |
| App/MemoraModel+Conversation.swift | workspace境界で失効を呼出し |
| App/MemoraModel+AI.swift | 範囲回答の世代、stage、groundedの開始/callback確認 |
| App/MemoraModel+ScopedAgent.swift | project agentの世代確認 |
| App/AIQuestionView.swift | 送信時世代と古い部分回答/保存の除外 |
| tools/checks/ProjectChatExecutionChecks.swift | 実lifecycle extension、in-memory保存の成功/失敗 |
| tools/checks/ProjectChatDispatchChecks.swift | 実send/cancel/delete実装と遅延dependency mock |
| tools/checks/run-motion-loading-checks.sh | 上記Swift 6チェックを追加 |

## 検証

`ProjectChatExecutionChecks`は本番のProjectChatExecution extensionを直接コンパイルし、依頼owner・旧世代・Task取消・停止直後の状態解除・遅いcleanupによる後継保護・完了履歴の保持・保存失敗時の非破壊を確認する。

`ProjectChatDispatchChecks`は本番のProjectChat/ProjectChatExecution extensionを両方コンパイルする。model/provider/資料取得/保存面だけをメモリ上のmockにし、次の実行を検証する。

1. 旧依頼の本文取得をsuspend → 停止 → 新規依頼を送信 → 旧取得を再開。旧依頼からmodel dispatchは0件、新しいbusy/stage/本文/jobが維持される。
2. model応答待ちでA → B → Aの世代を失効 → 新規依頼を送信 → 旧stream callbackと旧最終回答を到着。新しい依頼へ混入せず、新しい完了回答だけを追加する。callbackは取消済みTaskとは別のTaskから呼び、取消flagだけに依存しないowner確認も通す。
3. model応答待ちでchat削除 → 古いcallback/最終回答を到着。削除したchatを復活させず、job/owner/partial/busyが残らない。

両テストはSwift 6 modeで成功。架空の文字列/UUIDだけを使い、実SQLite、UserDefaults、Keychain、ユーザーファイル、APIへ接続しない。workspace切り替えは本番の失効methodを呼び出すmockであり、チームbackendや画面操作のE2Eではない。

- `bash tools/checks/run-motion-loading-checks.sh`: 成功。新しい2チェックと既存motion/loading/stream/予算/操作待機の回帰。
- `bash tools/checks/run-next-generation-checks.sh`: 成功。scope/privacy/provenance、索引、会話codec、agent loop、registry、MCP等の既存回帰。
- `bitrig preview -platform iOS`: 最終Debugビルド・プレビュー更新成功。log `2026-10-16T17-23-32-48f6b1cb.log`。初回のMainActor指定漏れは修正済み。
- `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`: 最終差分で成功。log `2026-10-16T17-25-38-270646ab.log`。両ビルドの警告は既存Share ExtensionのAppIntents metadata抽出省略1件。logはBitrigの当該project Builds/logs内。
- `git diff --check`: 成功。実装・隔離回帰は`30c615d`。

## 未検証・性能

実provider、実チームworkspace、実SQLiteの失敗注入、AIQuestionViewの切り替え画面操作、実機、VoiceOver、iPhone Releaseでの時間/メモリ/課金は未検証。今回の数値は合成テストのdispatch件数で、体感速度/料金の改善率ではない。全機能の実機回帰が完了したとは扱わない。
