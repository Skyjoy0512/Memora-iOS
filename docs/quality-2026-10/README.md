# Memora品質改善：検証可能な作業記録

更新: 2026-10-26。前回基点：`23230af5e0356a1a5f7d8d4e72ed22b5d937d704`。今回の開始時に再取得したmain：`cb23b3dfab31cf6521b393cd6864171eb1ce5682`（clean）。

**総合プロジェクトは未完了。** BYOK DeepSeekの「本文前に2MiB制限で失敗する」欠陥は修正・回帰検証済みだが、利用者の約50秒事象が同じ原因だったかは実ジョブ診断との照合が残る。HTTP timeoutの延長では対処していない。

今回のコードcommit `d1fae4a`、後続benchmark/UIを含む`9fe9ac9`は実GitHub Actions全6suite Green（[後続run](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40247229216)）。生成mode/最大2並列、実本文を区別する診断、ホストで測定した本文buffer改善、Keychain失敗時のlicense整合性、RAG混入低減を追加。実APIはユーザー指定で実行せず、速度/品質/料金A/Bと実機の50秒再発確認は未検証。最後の空白入力ガードは関連ホスト検査とDebug/ReleaseをPassし、別commitのremote結果と区別する。詳細はCとKを参照。

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
| [H：要約高速化](H_SUMMARY_SPEED.md) | 実測buffer Before/After、公式DeepSeek policy、生成mode、並列fixture、未実施A/B |
| [I：ライセンス保存](I_LICENSE_STORAGE.md) | Keychainの保存/削除失敗・再読込・期限・旧code保持 |
| [J：検索precision](J_RAG_PRECISION.md) | 27問の拡張corpus、混入率/Recall/Precision、残る語彙検索の限界 |
| [K：今回の到達点と残作業](K_FOLLOWUP_STATUS.md) | 実装/検証/Not Run/未実装の分類、外部許可と実機の境界 |

## 実装済みのまとまり

- `e4c140b`：CI SIGTRAPをlocale差まで特定し、両localeの契約比較へ修正。remote Green。
- `a05ddea`：reasoning/本文の開始を分離、HTTPごとの診断ID、usage/終了理由/ライフサイクル。
- `c477300`：本文append buffer。21試行・本文厳密一致のBefore/After。
- `1846897`：licenseのKeychain保存/削除失敗で成功状態へ進めない。
- `76e7b4a`：詳しさと生成modeを分離、旧データ互換、opt-in最大2並列/送信前の再検証。
- `d1fae4a`：RAGの弱一致/部分一致/重複除外、複数根拠を保つ評価拡張。remote Green。
- `06cfa0e` / `649cde9`：実Meeting codecの1,000/10,000件保存benchmarkと固定fixture。
- `798fe07`：要約engineの折返し/最大文字サイズの縦配置、実画像とE2E bounds検証。

以下は前回の修正（既存実装を継続利用）:

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

`git log --oneline 23230af..HEAD` で後続の検証・report commitも追跡できる。2026-10-26はGitHub反映依頼に従いGitHub mainへfast-forward pushし、remote CIを確認した。既存履歴の書換えはしていない。

## 次の優先事項

1. 実DeepSeek事象のjob ID/終了理由との照合。実API課金を伴う試験は無断実行しない。
2. 実機IME/OS期限/中断/保存保護/録音負荷の確認。
3. IP固定MCP/OAuthの実サービス互換性検証と、任意接続先の本番運用ポリシー。
4. 検索precisionはfixture上で改善したが混入が残る。実質問/holdout評価と、全量保存の実機benchmark/段階的移行設計。

既存データを削除/復元したり、Bundle ID/App Groups/本番設定を変更したりしていない。保存済み本文を再生成・一括書き換えせず、外部API・ツールの副作用も実行していない。
