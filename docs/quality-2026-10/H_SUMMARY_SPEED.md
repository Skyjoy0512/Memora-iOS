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

## 生成モードと公式仕様

既存の詳しさ（簡潔/標準/詳細）はそのまま。別の生成モードを追加し、古い設定・バックアップ・PendingSummaryJobは欠落fieldを標準としてdecodeする。長さ・テンプレート・出典・task JSONは変えない。選択だけで生成・送信しない。

2026-10-26に[DeepSeek Chat Completions仕様](https://api-docs.deepseek.com/api/create-chat-completion/)と[Thinking Mode](https://api-docs.deepseek.com/guides/thinking_mode/)を再確認。公式routeの`deepseek-flash`/`deepseek-v4-pro`にだけレビュー済みpolicyを適用する。標準は従来のrequestのまま。高速は`thinking.type=disabled`、高精度は`enabled`と`reasoning_effort=high`。両者に`max_tokens=65536`を明示し、推論OFF時の既定8Kへの縮小を避ける。推論ONの既定はhigh/64K、APIの出力上限は393216。モデルの自動切替はしない。

OpenAI/Anthropic/Google/OpenRouter/Qwen/Mistral等、custom endpoint、未知の登録モデル/旧aliasにはDeepSeek固有fieldを送らない。「非対応」と断定せず未検証として元のshapeを維持し、UIに説明する。高速/高精度の適用対象外でも既存の要約機能は利用できる。On-deviceのモデル設定も変更しない。

本番CloudAIServiceをoffline URLProtocolで動かし、全provider×4モデル×3モード×公式/custom経路でfield漏洩がないことをassert。HTTP失敗を別parameterで自動再送しない。継続前のauthorize失効で次のHTTP requestが出ないこともassert。生成モードは診断のprocessingMode code（高速0/標準1/高精度2）で区別する。

## 長文の制限付き並列処理

高速かつ上記レビュー済みDeepSeekだけ最大2並列。標準・高精度・未知routeは従来の逐次。入力分割と各promptは変えず、index順で全区間を揃えてから既存の1回の統合を行う。各HTTP送信/継続前に現在の会議fingerprint・権限・workspace・jobを再検証する。1件失敗なら他の子taskをcancelし、残りの区間・統合・部分保存・自動再送を行わない。成功分はそのrun内だけで使い、永続的な部分結果の再利用は未実装。中断時に既に実行中の最大2件が課金される可能性はUIに明記。

`SummaryPipelineChecks`は実MeetingSummarizer/分割/統合prompt/parserに制御可能な通信fixtureを接続。4区間各30秒+統合60秒の仮想時計では逐次180秒、2並列120秒。到着が逆順でも時間順・segmentIDを保持し、統合で全文を再送していないこと、失敗/中断/権限失効時に後続requestがないことを検証。これは待ち時間モデルの検証であり、実APIの33.3%高速化を実測した結果ではない。品質・料金・rate limit・p50/p95/maxの実DeepSeek比較はNot Run。

## 採用を保留した最適化

- 標準の非推論化: A/B品質比較なしで既定を変更しない。高速を明示選択した場合だけ候補を評価できる実装にした。
- Markdown/JSONの削除: actions、keyPoints、decisions、未決、根拠、履歴に利用するため、決定的抽出の同等性とLLM事実精度を確認するまで維持。候補テンプレートの絞込みは既存実装を再利用し重複実装しない。
- token上限の削減、3並列以上、自動モデルfallback/再送: 打切り・費用・rate limit・重複請求リスクがあり未採用。
- 暫定要約の確定/履歴/taskへの反映: 未検証の部分応答を保存しない。今回のUIは実段階と実文字数のみ。先行プレビューはNot Implemented。

保存の原子的commitと入力再検証は維持。全Meeting encodeは別の未完了課題であり、この変更によるSQLite/起動/録音/iPhone CPU・電池の高速化は主張しない。
