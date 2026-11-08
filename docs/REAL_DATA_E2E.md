# 実データE2Eの範囲（2026-11-08）

フィクスチャ検証と実データ検証を混同しないための境界。既定のテスト実行は
外部ネットワーク・実音声・クラウドLLMを使わない。

## 実Web（オプトイン）

```bash
MEMORA_REAL_WEB_URL='https://（オーナーが許可したURL）' \
  bash tools/checks/run-real-web-e2e.sh
```

- 1回だけ指定URLへHTTPS取得する。サンプルサイトへは接続しない。
- 確認する: URL取得→本文抽出→資料としてSQLite保存→再起動後も原文が読める→
  端末内AIへの質問→回答または「できない」という正直な表示→引用リンクで原文へ戻る。
- 確認しない: 429/リダイレクト/文字化け/巨大記事/プライバシー変更の網羅、
  クラウドLLMの要約品質。これらは手動で同じURL群を用意して確認する。
- 要約・回答は端末内モデルのみ。クラウド課金・APIキーは使わない。
- URLを付けない通常実行ではテストはskipし、ネットワークへ出ない。

## 実音声（手動・未実施）

1. 同意済みの日本語音声を用意し、端末のファイルAppからMemoraへ音声として取り込む。
2. 設定 › AIと要約 › 文字起こしが端末内であることを確認して文字起こしを開始する。
3. 要約が完成したら、要約から質問し、12秒など実時刻の引用を開いて再生位置を確認する。
4. 失敗時は原本が残り、完成要約が捏造されないことを確認する。
5. 可能なら10分・1時間・複数原本で、引用時刻・話者・再開位置を照合する。

クラウドSTT/LLMは今回の対象外。実音声が無い場合、`source-audio-citation.e2e.ts`の
合成字幕による経路検証だけをPASSとし、実STTの証拠にはしない。

## 異常系の既存カバレッジ

| 事象 | 既存の検証 |
|---|---|
| 保存失敗・下書き保持・再起動復旧 | `project-source-recovery.e2e.ts`, `project-source-photo.e2e.ts` |
| 中断状態の再読込（取得の自動再開なし） | `project-source-interruption.e2e.ts`（外部URLのため通常実行では使わない） |
| 添付順・解除・再起動 | `project-source-note-attach-order.e2e.ts` |
| 録音の中断・SIGKILL復旧・AAC検証 | `recording-lifecycle.e2e.ts` |
| 容量不足・writer overrun・変換失敗 | 録音系host runner（fixture） |
| 古い非同期結果の混入 | `AgentConversationLoopChecks`等のhost runner、録音run coordinator |
| 同意失効・チーム境界 | `ArtifactProvenanceChecks`, `PersonPrivacyChecks` |

実Webの404/429/リダイレクト/本文なし/文字化け/巨大記事/再試行は未実施。
実音声のSTT→要約→引用→再生ジャンプも未実施。
