# 要約性能の測定

利用者報告: 文字起こし済み1時間相当の要約が120秒超。これは現環境で再現計測した値ではない。目標60秒、次段階30秒、録音終了後の追加待ち10〜20秒は未達成・未検証。

要約以外のSTT、話者分析、取り込みから保存までを混同しない。既存 `AudioProcessingDiagnostics` のsummary / recognition / persistence等のspanと、`SummaryDiagnostics`のrequest別タイムラインを関連付ける。本文・キー・エンドポイント・ユーザー原文は診断に記録しない。

集計ライブラリ `tools/evaluation/quality_metrics.py` はP50/P95（nearest rank）/最大、既知サンプル数、不明サンプル数を返す。未提供usage、料金、端末CPU・電池を0に置換しない。TTFT、first reasoning、本文生成時間は別列。初回推論イベントは「推論処理全体の実時間」を意味しない。

旧/新は同一原文・指示・モデル・推論・出力予算・データ版・プロンプト版で比較する。cold/warm、1/2/3/4並列は別cohortとして複数回測定。API混雑とrun差を報告し、仮想時計のscheduler試験を実APIの秒数として扱わない。

実API・実機を使わずに証明できるのは、入力のbyte削減、処理計画、キャンセル、正しい順序、ローカル実装の所要時間まで。API token削減率・コスト低下・60秒以内の達成は別途計測が必要。
