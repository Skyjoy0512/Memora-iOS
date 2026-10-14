# Memora 品質改善 — 2026-10-14

## 最新mainの監査

`Skyjoy0512/Memora-iOS` main をfetchし、`a6deb20084f3f07372de3fd55bc20fc358c354d3`
とローカルmainが一致すること、作業ツリーが空であることを確認した。
AGENTS、NEXT_GENERATION_AI、IMPROVEMENT_BACKLOG、ASK_AI_PLUGINS、
AI_PLUGIN_MCP、PROJECT_WORKSPACE_V2、MONOCHROME_DESIGN、MAIN_NAVIGATION、
PERFORMANCE_OPTIMIZATIONと実コードを照合する。古い文書のタブ順ではなく
現コードのJournal / Library / Ask AIを基準にする。

| 領域 | 開始時の実装と確認範囲 | 残る境界 |
| --- | --- | --- |
| 会話 | 共通AIResponseText、実SSE、AgentConversationLoop、別々の保存履歴 | tab復帰で消去、global会話本体は非永続、project/recordのUIは別 |
| 操作 | globalの承認付き内蔵toolとBYOK/MCP | 添付はgroundedのみ、@と添付の併用をUIとmodel両方で拒否 |
| スコープ | ScopedAgent / RecordAgentのread-only loopと現在の権限検査 | project/recordの変更toolは未提供。実BYOKの往復E2E未確認 |
| Intelligent UI | bounded native8種類、Markdown fallback、承認付きタスク完了 | 候補編集/一括登録は未対応。JSON検証は数値の事実性を保証しない |
| ソース | PDF20ページ、画像OCR、UTF-8、YouTube公式oEmbed/thumbnail | 一般Web本文とOffice未対応。YouTube字幕/画像vision未対応 |
| 検索 | SQLite FTS5、Japanese2-gram、project派生索引、抜粋上限 | 正解資料付きRAG評価は未整備。ベクトルDBは追加していない |
| 連携/skills | native管理、明示@、ローカルランキング、Markdown手順 | Gmail/Notion/MCP/BYOK実認証E2E未確認。Drive/GitHub OAuth未実装 |
| iOS | Ask AI Widget、データWidget、6 Intents、録音Live Activity | App Group未設定。実データWidgetは未設定表示。AI Activity未実装 |
| 性能/保存 | 共通抽出、100msのstream公開、leaf、直列SQLite保存、backup旧版読取 | 今回の実機性能/実backup復元は未検証 |

「コードがある」「ローカルfixtureを通った」「Simulator操作済み」
「実機/実サービスで成功」を分けて記録する。外部認証情報やユーザーの記録を
検証fixtureへコピーしない。新しい有料契約、backend配備、ID変更は行わない。

## P0-1: 会話継続

- `didChangeTab`で会話を消す処理と、system linkからの暗黙のnew chatを除去。
  明示的なnew chatは従来どおりrequest ID、Task、承認/質問を取り消して空白にする。
- `AIConversationSnapshot`はworkspace別の追加SQLiteキー。履歴/record/mediaの
  旧形式は変更しない。新規インストールではresume documentがなく空白のまま。
- 600msの静かな区間にまとめて保存し、tab離脱/backgroundではcheckpoint。
  毎tokenの書込を避ける。背景でOSが即停止した場合の最後の未確定本文は保証しない。
  workspace切替だけは直列queueへ同期確定し、すぐ戻っても古いcopyを読まない。
- 最大2,000turn/8MiB（JSON escape分を保守的に見積もる）。超過は切捨てず
  保存失敗を表示する。完了済みexchangeの既存historyは引き続き保存する。
- 引用、engineの表示、完了したresident投稿を復元。未完了residentは投稿しない。
  中断した通常回答は未完了表示にし、自動再送せず、再試行の操作も復元しない。
- 生成UIの変更ID、tool policy、承認continuation、cloud sessionの許可集合は
  保存しない。復元した回答の再利用には既存provenance/現在のprivacy再検証が必要。
  このresume documentは実行履歴やbackup manifestの代替ではない。

検証: `AIConversationSnapshotChecks`は実codecと復元を呼び、引用/metadata/
resident、empty、別workspace、version/role/重複ID/容量、権限の非復元、中断の
安全表示を確認。既存21スイートを含む22スイートが成功。ネットワークを使わない。
最終Bitrig build `2026-10-14T19-35-26-cc04365c.log`成功（既存metadata警告1件）。
最初のprivate property参照エラーを修正して再buildした。iPhone 18 Pro Maxでは
既存履歴を送信せず再開し、Library往復で同じ会話が残ることを確認。
app switcherで終了→App Libraryから再起動→Ask AIで質問/回答/再送拒否の
表示を復元した。明示的なnew chatで空白と無効なnew-chatボタンへ戻った。
変更前/再開/復元/空白のスクリーンショットを観察。履歴・記録の追加削除、
有料推論、実外部アカウントの取得は行っていない。

## 次の実装順

1. 既存のuser messageとscroll追従を共通化。UIだけを共有して履歴/権限は分離。
2. prepared attachmentを一度だけagentへ渡し、失敗時に入力と添付を維持。
3. タスク候補の編集と既存approval/実登録経路を接続。保存結果を先に確認。
4. ソース状態とOffice、一般Webの安全な取得、正解付きRAG評価。
5. 連携/skillの評価、全画面のappearance/accessibility、backup実復元、
   Apple識別子/App Group準備、実機性能と実サービスE2E。

現時点でプロジェクト全体の完成とは扱わない。
