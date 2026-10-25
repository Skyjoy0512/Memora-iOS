# 性能・検索品質の計測

## 2026-10-26の追加測定

本文バッファのBefore/Afterは [H](H_SUMMARY_SPEED.md)、検索の同じ拡張corpusでの比較は [J](J_RAG_PRECISION.md)。以下は既存の全Meeting保存方式の**基準値のみ**で、改善率ではない。

実`Meeting`/`TranscriptSegment`/`TemplateSummary` codecと実`LocalStore.applyBatch`をSwift `-O`で実行。各recordは20発言・5分相当の合成日本語、音声/写真なし。1件の要約だけ変更し、全Meeting配列と空tasks/jobsを原子的に保存、21試行。caseごとに別process・SQLite、試行ごとautoreleaseを解放し、再open/decodeで変更外の全record/原文の厳密一致をassert。メディアAPIは呼ばれたら失敗するfixture。実app DBを開かない。

| 件数 / JSON bytes | 配列copy median/p95/max ms | 全量encode median/p95/max ms | SQLite batch median/p95/max ms | 合計 median/p95/max ms | 21試行のCPU ms | loop終了時process peak RSS bytes |
| --- | --- | --- | --- | --- | ---: | ---: |
| 1,000 / 6,075,905 | 0.051/0.133/0.137 | 47.051/52.490/53.960 | 25.533/54.656/62.441 | 74.184/101.186/111.426 | 1,182.787 | 68,567,040 |
| 10,000 / 60,768,905 | 0.535/1.011/1.389 | 457.843/481.189/508.781 | 117.313/147.344/174.164 | 577.966/628.811/684.334 | 11,874.407 | 536,870,912 |

再実行: `python3 -B tools/checks/run-meeting-persistence-performance-checks.py`。optimizationにも追加。CPUはtimed loop中のprocess user+system CPU合計、RSSはloop終了時点のprocess高水位（fixture/encoder/保存bytesを含む）で、iPhoneのCPU使用率・アプリRSSではない。他のビルド/検査との同時負荷があり、比較最適化のBefore/Afterとして扱わない。

上表はUUID・全日時（privacy.updatedAtを含む）を固定した最終fixture。初回試行の579.198ms/60,837,779 bytesは既定privacy日時が可変だったため、再現性を修正して再測定した。負荷が大きい同時実行では同じ方式のp95が約982msにも達した。小さな差を速度改善としない。

10,000件の全量encodeは明確な負荷。要約確定の同期原子的commitをそのままasyncへ移すだけでは、await中の他record/task更新を古い配列で上書きする危険がある。今回はschemaやtransaction境界を急に変えず、単一record更新方式・再検証付きoff-actor encode・段階移行/rollbackを次段とする。要約保存/起動/実機の大幅高速化は未達。SQLite値自体も50秒失敗を説明しない。

すべて合成fixtureのMacホスト計測。iPhone実機、Simulator UIの起動/スクロール/CPU/電池の計測ではない。
ビルドや他の検査と並行した測定を含むため、小さい時間差を最適化の効果としない。

## MCP/保存の追加修正後の再測定

`memora-quality-ns8tghh9` 全体検査の実測（ms）:
ランキング1,000件 median 6.769 / p95 6.868 / max 6.883、SQLite batch 1,000件 8.742 / 9.115 / 11.244。
検索はhit@1=11/11、Recall@3=1.000、MRR=1.000、unrelated-sent=0.500、棄権1/1、p50=0.56 / p95=13.62。
検索precisionは改善しておらず、IP固定やパス修正による速度向上も主張しない。
診断保持は開始+末尾255イベント（進行中lastToken追加1件）/12ジョブの上限を維持し、長い処理の最終結果の可観測性を改善。CPU/RSSのBefore/Afterは未計測。

## 今回の変更前後

| 対象 | Before (`23230af`) | After | 評価 |
| --- | --- | --- | --- |
| DeepSeek SSE 2,178,128 byte/9,000 reasoning delta | 実行した本番decoderが本文の前にexecutionLimit | 同じfixtureが最終stopまで完了、非表示推論を保持しない | 信頼性・保持量の改善。速度/実RSSの改善率は未計測 |
| 検索hit@1、Recall@3、MRR | 11/11、1.000、1.000 | 11/11、1.000、1.000 | 既存の正解を維持。12問だけのfixtureで一般化しない |
| 不一致質問の棄権 | 1/1 | 1/1 | 最終Contextの既存棄権を維持。index自体の無条件200chunk fallbackは今回禁止 |
| 送信した根拠の無関係率 | 0.500 | 0.500 | 未改善。単一のhit率だけで検索の完成としない |
| RAG検索+Context、p50/p95 | 0.74/22.95ms | 個別再実行3.13/20.25ms、最終全体検査内0.47/12.49ms | いずれも同じ合成corpus。測定負荷が異なるので高速化と解釈しない |

再実行: `python3 tools/checks/run-project-search-quality.py --baseline-ref 23230af5e0356a1a5f7d8d4e72ed22b5d937d704` と、引数なしの現行検査。
根拠のproject/権限、削除・更新・失効、長いPDFのページ抜粋も実FTS5とContextで検査する。

## 現行コードの基準値（ms）

以下は今回のホスト全体検査の実測例。過去の最適化を今回実装したと称さない。
`tools/checks/run-optimization-checks.py`、21試行のmedian/p95/max。

| 処理 | 件数 | median | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| 記録ランキング | 1,000 | 6.689 | 7.120 | 7.818 |
| ライブラリsection作成 | 1,000 | 2.718 | 2.746 | 2.789 |
| SQLite batch | 1,000 | 8.622 | 9.053 | 11.312 |
| ジャーナル関連の所有権一括集計 | 1,000 | 0.400 | 0.411 | 0.416 |
| ID index参照 | 1,000 | 0.174 | 0.195 | 0.201 |

測定ログ: `/Volumes/WorkspaceSSD/Development/Agents/Codex/tmp/memora-quality/memora-quality-g3mec4x7/optimization.log`。
最終の固定ソース検査は [C](C_TESTS.md) に別記する。先行の並行負荷が大きい実行ではSQLite p95=20.390ms、ranking p95=16.791msだった。測定中の他の処理の影響を無視して差分を改善率としない。

## まだ測定していないもの

- 実機の起動/初期描画、録音中CPU・メモリ・電池、画像/PDF/Officeのメモリピーク、長時間推論中のUIフレーム時間。
- 1件更新での全Meeting配列encodeのサイズ別CPU/RSS・p95。直列queue上での順序保護は維持したが、単一record更新方式への移行は行っていない。
- 起動・スクロール・ストリーミングの実機Before/After。体感やホストアルゴリズムの値で代用しない。

OSLogの要約タイムラインは処理区間を測れるが、CPU/RSS/描画フレームを測るものではない。
次の性能変更は、同一デバイス/fixture/ビルド条件で基準値を確保してから行う。
