# 要約ベンチマーク結果

基準 `183b1226`、実施日2026-11-14。生成/評価の実モデル呼び出し0件。利用者の「実モデル評価は行わず未検証として報告する」指定を維持。

| 指標 | 改善前 | 改善後 | 検証状態 |
|---|---|---|---|
| 実API要約時間（60分原文） | 利用者報告120秒超 | 不明 | 同条件測定なし |
| 実API費用・token・TTFT・推論時間 | 不明 | 不明 | API実行なし |
| J-MeetEval公式総合スコア | 不明 | 不明 | Judge未実行 |
| 固定データ監査 | 未導入 | 197件・16カテゴリ | byte照合・SHA256確認済み |
| 評価器の単体テスト | 未導入 | 7件成功 | オフライン、モデル品質ではない |

実機の電池・発熱・メインスレッド負荷は未計測。以前の整形fixture結果は [別報告](adaptive-summary/REPORT.md) に保持する。本書の性能目標の達成証拠として転記しない。

Phase 1追加検証: 通信を遮断して実行した固定版J-MeetEval上流テスト107件成功（0.49秒、Macホスト）。これは評価コードの回帰試験時間であり、LLM生成時間・品質ではない。

Phase 2のローカル入力比較（1,000発言、同一原文）: 199,999 → 151,139 bytes、24.43%減。原文本文・改行・話者・順序・UUID往復を検証。トークン数、LLM品質、API料金・待ち時間は未測定。


容量計画のオフライン検証: 1,000発言・従来ID表現112,889文字の同じ合成原文で、旧閾値なら3部分+最終の4 requestを計画する。新経路はレビュー済みの1M級モデル容量に全文が収まり、実オーケストレーター+通信mockで1 requestとなることを確認。最初・最後の発言を含め全原文を送信する。実APIの品質・応答時間・料金の4倍改善を意味しない。

巨大入力の4部分+統合、並列数1/2/3/4、到着順逆転、rateLimitedでのfail-stopを無料テストで確認。標準/高精度の推論設定は維持。仮想時計の120秒などは実API計測ではない。

2026-11-15追加: 同一合成長文のproductionオーケストレーター+通信mockで、初回4部分+最終の5 request → 長さ/表示順変更後はcache再利用で最終1 request。全区間を順番どおり最終promptへ保持し、原文/話者/owner/workspace/account/認証/権限/model key変更と拒否時0追加送信を検証。実API速度・費用・品質の改善率ではない。SQLite再起動、TTL/LRU/容量、破損hash、旧leaseの書戻し拒否を実SQLiteで検証。

SSEバイト/SSE/JSON解析がmain thread外、表示callbackがMainActorで動作することをhostで確認。2,178,128-byteの合成入力と仮想30〜180秒受信を通過。これらの所要時間を60分録音のAPI性能として扱わない。

階層groupの1/2/3/4並列をproduction reducerで検証。4 groupに対してmerge呼出しは各4回のまま、到着順を逆にしてもab/cd/ef/ghの順序を保持。429で初期2 worker以降の送信を止めた。原文prefixの同一性と既存pipeline/cache回帰を確認。iOS preview 2026-11-15T04-37-47-73cf439d.log成功（既存11警告）。実APIでのヒット率・速度は不明。

計測/比較基盤の追加検証: 開発Python環境の全11単体テスト成功（0.408秒は評価器のテスト時間）。197件/16カテゴリの固定データ監査、300 requestを表示切捨て後も集計、4,097件で欠測明示、実transportの429 outcome・bounded continuationを確認。JSON fallbackのbyte receive/parseもhostでoff-mainを確認。実モデルのスコアは未取得。ログは外部作業ディレクトリのphase0-metrics-* / phase1-all-offline-final.log / phase2-single-serialization.log / phase0-request-failure-metrics.log。
