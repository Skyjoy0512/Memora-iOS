# 接続・配布状態（コード調査、2026-10-25）

「実装済み」は実サービス運用済みを意味しない。今回、実機・外部アカウント・本番サービスへの接続はしていない。

| 機能 | 分類 | 現在の実装と不足 |
| --- | --- | --- |
| Memora Intelligence | バックエンド未接続 | `MemoraIntelligence` はサーバーURL/発行tokenを必要とするOpenAI互換経路。サーバー・credit精算は未構築。プロバイダー鍵をアプリへ内蔵しない |
| StoreKit課金/サインイン | 一部実装 | `MemoraModel+Account.choosePlan` はローカル設定。StoreKit取引・検証・購読復元は未接続。課金済みと扱わない |
| 法人ライセンス | 実装済み・実機未検証 | Ed25519検証とKeychain保存。今回保存/削除失敗時の整合性を修正、fixtureで再読込/期限/旧code保持を検査 [I](I_LICENSE_STORAGE.md)。実Keychainロック/実コードの実機検証、サーバー契約照合は別 |
| TeamBackend | バックエンド未接続 | `MemoraModel.teamBackend = UnconfiguredTeamBackend()`。チーム作成/参加を拒否。サーバー・認証・同期の実装が必要 |
| CloudKit共有 | 一部実装 | `CloudSharingService` の読み取り専用snapshot経路。メディア同期/統合/競合解決は未実装。capability/container/実iCloudアカウント確認が必要。実機未検証 |
| Share Extension | 実装済み・実機未検証 | 共有取り込みと安全なInboxのホストfixtureあり。実共有元・署名・App Group連携は未検証。設定キーが未指定なら接続済みと表示しない |
| Widget App Groups | 一部実装 | `MemoraWidgetSnapshotStore` は `MemoraWidgetAppGroup` が必要。実container共有は未確認。ライブ録音機能の既存動作を削除しない |
| Dynamic Island / Live Activities | 実装済み・実機未検証 | `MemoraModel+Capture`が実録音開始/一時停止/終了のActivityを更新、古いActivityを終了。`NSSupportsLiveActivities=true`。実ロック画面/Island・バックグラウンド録音との実機連動は未検証 |
| Gmail | 実装済み・実機未検証 | PKCE/read-only OAuth、refreshのKeychain保持、権限・承認・失効のfixtureあり。現在のProject.jsonにはGoogle client IDなし。実Googleログインは未検証 |
| Notion | 実装済み・実機未検証 | 利用者token/parent pageによる保存・分割・部分失敗回復。fixtureでHTTP/権限競合を検査。実workspaceへの作成は未実施 |
| MCP OAuth | 実装済み・実機未検証 | PKCE/token更新・権限失効、IP固定POST/TLS、MCP sessionと切断競合のfixtureあり。クライアントのDNS再解決経路は修正。ブラウザー/実サービス/実機、HTTP互換性と本番運用保証は [G](G_MCP_STORAGE_FOLLOWUP.md) の未検証事項として残る |
| Google Drive / GitHub連携 | 未実装 | 設定/選択肢だけでサービス接続を実装していない。MCPに同名ツールを登録したことをネイティブ連携完成としない |
| 会社Officeテンプレート | 一部実装 | ローカル解析・OOXML保持/置換のPoC、XML/ZIP・原本非変更・SQLite検証あり。Officeでの組版/ページ送り/実テンプレート再現性は未検証 |

この調査では「実装済み・実機検証済み」に分類できる上記接続機能はない。Bundle ID、App Groups、署名、恒久containerは無断変更していない。

## 変更の追跡

各まとまりは独立commit。`git log --oneline -- docs/quality-2026-10 App` と、各報告の再実行コマンドで追跡できる。
2026-10-26はユーザーのGitHub反映依頼に従ってGitHub mainへ通常のfast-forward pushを実施。[CI](CI.md)にコードcommitごとのremote検証結果を記録。署名/Bundle ID/課金設定を変更したわけではない。
