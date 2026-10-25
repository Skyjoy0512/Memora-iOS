# 要約の高速化と比較（2026-10-26）

## 本文バッファ：ホストで測定済み

Before=`cb23b3d`。同じproduction accumulator、Swift `-O`、同じ合成日本語・絵文字、21試行、各case別process、各trialでFoundationのautoreleaseを解放。本文の厳密一致と終了検証を全試行でassertする。

再実行: `python3 -B tools/checks/run-cloud-stream-performance-checks.py --baseline-ref cb23b3d`、引数なしで現行。同一Macホスト。API/ネットワークなし。

| API / 断片数 / 本文bytes | Before median / p95 / max (ms) | After median / p95 / max (ms) | process peak RSS Before → After (bytes) |
| --- | --- | --- | --- |
| Chat / 1,000 / 85,000 | 6.026 / 6.485 / 7.709 | 4.051 / 4.246 / 6.672 | 8,503,296 → 7,569,408 |
| Chat / 5,000 / 425,000 | 33.916 / 39.312 / 43.279 | 19.963 / 21.680 / 23.799 | 11,550,720 → 9,502,720 |
| Chat / 10,000 / 850,000 | 91.408 / 101.350 / 107.853 | 40.099 / 41.578 / 46.102 | 14,827,520 → 13,942,784 |
| Anthropic / 1,000 / 85,000 | 6.311 / 6.635 / 7.234 | 6.459 / 7.153 / 7.856 | 10,076,160 → 9,732,096 |
| Anthropic / 5,000 / 425,000 | 39.895 / 40.807 / 43.342 | 32.280 / 33.192 / 33.844 | 13,156,352 → 12,599,296 |
| Anthropic / 10,000 / 850,000 | 104.460 / 115.815 / 120.701 | 64.567 / 70.166 / 72.924 | 22,446,080 → 18,333,696 |

大きいChat本文でmedian 56.1%、Anthropic本文で38.2%のローカル処理時間減。ただし最小Anthropic caseは改善していない。RSSは各process全体のhigh-water markであり、アプリのメモリピークや差分allocationではない。CPU比率・UIフレーム時間はNot Run。

原因はAny dictionary内の全文aliasと小片ごとの全文再構築。本文を独立したappend bufferへ変更し、Anthropicは通常順ならappend、逆順/interleaved blockだけindex順に再構築する。公開済みsnapshot、Unicode、複数block順、2MiB本文上限、32MiB wire上限、tool/reasoning文脈、最終検証は維持。

これは約40〜105msのホスト処理の比較であり、50秒失敗の原因確定や実プロバイダー生成時間の改善ではない。推論ON/OFF、5/15/30/60/120分の会議内容の品質・料金・TTFT・TTFC比較は有料API未許可のためNot Run。医療・福祉・商談・多数決定・多人数のLLM事実精度も合成通信で代用しない。

## 診断の正確性

`a05ddea`で推論開始と初回本文トークンを分離。各HTTP requestに別UUIDを付け、継続・並列でもfirst/last tokenを混同しない。使用量はproviderの有効な整数counterだけ採用し、未提供の推論token/料金は推定しない。provider終了理由は固定allowlistのみ記録。実行中ジョブのforeground/background遷移を記録する。本文・推論本文・秘密は記録しない。

実ユーザーの50秒失敗ログはまだ受領していない。既知の受信上限修正の回帰Passと、実ジョブの完全解決確認は別である。
