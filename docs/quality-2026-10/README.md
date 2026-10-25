# Memora品質改善：検証可能な作業記録

2026-10-25。GitHub mainの調査基点：`23230af5e0356a1a5f7d8d4e72ed22b5d937d704`。

**総合プロジェクトは未完了。** BYOK DeepSeekの「本文前に2MiB制限で失敗する」欠陥は修正・回帰検証済みだが、利用者の約50秒事象が同じ原因だったかは実ジョブ診断との照合が残る。HTTP timeoutの延長では対処していない。

| レポート | 内容 |
| --- | --- |
| [A：要約タイムアウト](A_SUMMARY_TIMEOUT.md) | 再現したDeepSeek欠陥、経路、長時間試験、復旧、診断、未確定部分 |
| [B：コードレビュー](B_CODE_REVIEW.md) | P0/P1の修正と、MCP実サービス互換性・検索precision・保存負荷などの残課題 |
| [C：テスト](C_TESTS.md) | Pass/Fail/Not Run、失敗後の再検証、実環境との境界 |
| [D：性能](D_PERFORMANCE.md) | 実測値、Before/After、計測していない指標 |
| [E：UI/UX](E_UI_UX.md) | 実Simulator画像、Light/Dark・Dynamic Type・編集、未検証画面 |
| [F：接続/配布](F_CONNECTIONS.md) | 実装/未接続/部分実装の区別、署名・アカウントが必要な箇所 |
| [CI](CI.md) | GitHub Actionsの無効なcontext修正、remote再実行との区別 |
| [G：通信/保存の追加修正](G_MCP_STORAGE_FOLLOWUP.md) | MCP/OAuthのIP固定・session競合、保存パスの正規化、長い診断の終端保持と再検証 |

## 実装済みのまとまり

- `5bc9df6`：長時間DeepSeek SSE、応答の完全性、診断、永続ジョブ/安全な中断、Foundation Modelsのエラー分類。
- `8fd1646`：GitHub Actionsのcontext修正。
- `6de1e19` / `595ff04`：yomiyasu 2.4.0追従と固定revision/意味保持の回帰検査。
- `8f57987` / `6bb98dc` / `2bfb27e`：数値・単位・符号・日時・条件/否定の根拠照合、表示サンプルの整合。
- `d7f94d3`：@記録にskill/toolを追加してもデータ参照範囲を広げない、検索不一致fallbackの限定。
- `1711137` / `50d36e0`：日本語の確定文字・native選択・書式の保持、全文選択paste/SQLite厳密一致のE2E。
- `db605c1`：図解と表示サンプルの本番相当fixture/native編集検証。
- `ed2969d`：MCP/OAuthの検査済みIP/TLS固定、厳密なHTTP/JSON/SSEとsession・切断競合の回帰検査。
- `acef618`：保存先の既存親を正規化し、新規ファイルの誤拒否を防止。
- `6a167fb`：診断の開始と末尾を保持し、長文処理の最終保存/失敗理由を失わない。

`git log --oneline 23230af..HEAD` で後続の検証・report commitも追跡できる。全変更はローカルcommitに分割し、手動pushはしていない（Bitrig公開）。

## 次の優先事項

1. 実DeepSeek事象のjob ID/終了理由との照合。実API課金を伴う試験は無断実行しない。
2. 実機IME/OS期限/中断/保存保護/録音負荷の確認。
3. IP固定MCP/OAuthの実サービス互換性検証と、任意接続先の本番運用ポリシー。
4. 検索precisionの改善と、全量保存の実機benchmark/段階的移行設計。

既存データを削除/復元したり、Bundle ID/App Groups/本番設定を変更したりしていない。保存済み本文を再生成・一括書き換えせず、外部API・ツールの副作用も実行していない。
