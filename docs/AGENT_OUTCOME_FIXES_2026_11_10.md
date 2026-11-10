# AI操作の承認・変更結果・再試行

## 修正

`requestAgentApproval`は承認結果だけを返す。承認の時点で`didChangeData`を立てない。
各ツールは`AgentToolOutcome.dataChange`で結果を返し、共通の`runAgentTool`が会話へ集約する。

- `none`: 読み取り、拒否、保存前の失敗、重複／変更なし。
- `committed`: ローカル保存、予定追加、Notionのページ作成を確認した場合。
  Notionでページ作成後の追記だけ失敗した場合も、実際に変更済みとして扱う。
- `unconfirmed`: 変更する可能性のある外部処理を開始し、変更内容を確認する受領証がない場合。
  MCPは成功応答だけでは変更の有無を確認できないため、読み取り専用以外はこちらに留める。

プロジェクト・メモリ・ジャーナル・資料・メール下書き・タスク追加／更新・記録移動・
カレンダー予定・Notion・MCPを対象にする。ローカル失敗や全件重複では変更済みにしない。
一度確認した変更／結果不明の状態は後続の読み取りで消さない。

`hasUnconfirmedDataChange`を会話の再開データにも保存し、結果不明の外部変更と中断された
処理の再試行を制限する。古い保存データは任意フィールドなしでも読み込める。
過去の`didChangeData`は安全のため保持する。復元から操作や承認を再実行しない。

## 検証

- `run-agent-outcome-checks.py`: 本番の承認待機、結果集約、再試行判定と、
  メモリ／プロジェクト／ジャーナルの保存分岐を実行。保存先とプロバイダーはfixture。
- `run-artifact-provenance-checks.sh --task-proposals`: 実SQLiteで承認後の保存、
  保存失敗、編集された候補、全件重複・部分重複・再オープンを検査。
- 同スクリプトの通常実行と`--calendar-interface`: メール下書きの実SQLite保存、
  失敗・権限失効と、変更フラグが立たないカレンダー読み取りの承認を検査。
- `run-notion-agent-checks.sh`、`run-mcp-agent-checks.sh`: 保存／結果不明／
  部分保存・失敗・読み取り専用・承認拒否を本番ツールで検査。通信はfixture。
- `run-conversation-evidence-checks.sh`: 結果不明フラグの保存復元・旧データ互換・中断時の保護。
- `run-next-generation-checks.sh`の広域回帰と、変更箇所の関連検査が成功。
- iOSプレビューを更新。実サービスの送信成功・実EventKit・実機検証とは区別する。

## 次の修正対象

破損したcomposer下書きの復旧UIを優先する。現状は起動時の`DraftStore.readAll`失敗が
記録本体の読み取り失敗と同じ保存保護へ入る。保護を一括解除せず、下書きの元バイトを
SQLiteの別キーに退避する処理と、記録本体の健全性確認を分ける必要がある。
この復旧UI・退避処理はまだ実装していない。

記録全体の保存性能、バックアップmanifestの読み込み上限、Undo保存失敗時の再試行、
CloudKit一時データ削除失敗後の再起動をまたぐ再試行も残る。
