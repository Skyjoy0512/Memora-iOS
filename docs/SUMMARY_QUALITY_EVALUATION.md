# 要約の品質評価

[適応型要約の35ケース](adaptive-summary/COVERAGE.md)と[同一抽出fixture比較](adaptive-summary/COMPARISON.md)を維持する。生成モデルの品質を、Swift整形処理のfixture成績で代用しない。

## Level 1（APIなし）

`python3 tools/checks/run-summary-evaluation-checks.py` は固定J-MeetEvalの全ファイル・197件・16カテゴリを監査し、Precision/Recall/F1、重大誤りゲート、不明値の保持、同条件比較のテストを実行する。`run-quality-checks.py`から実行する。依存追加なし。

`tools/evaluation/quality_metrics.py` は独立に付けたゴールドIDと人手照合済みの予測IDを比較する。facts / decisions / actions を別々に集計する。未対応の予測IDは要レビューとして採用を止める。確認された未根拠の予測・重大誤りは平均に関係なく不合格。言い換えを文字列一致だけで判定しない。レビュー未了をレビュー済みと表示しない。

公式ルールチェッカーの実行環境・コマンドは [J-MeetEval統合](JMEETEVAL_INTEGRATION.md) を参照。テスト専用応答を生成してスコア改善を演出しない。保存済み本番相当応答が無い場合、品質スコアは不明。

## Level 2 / 3（今回は実施しない）

生成モデルと評価モデルは独立して固定する。実行識別子、アプリのコミット、データ版、原文SHA256、指示SHA256、モデル、プロバイダー、推論・出力設定、キャッシュ条件、並列数を記録する。同一条件比較の必須情報がない場合は高速化判定を拒否する。独立評価用資格情報と実行・費用上限が必須。通常CIに課金経路を追加しない。

5/15/30/60/120/180分超、前半決定の撤回、条件付き結論、担当・期限未言及、表記揺れ、専門用語、多言語、雑談、日常・講義・Web/PDF/字幕・注入文などは長文ゴールドの追加対象。既存35ケースは網羅性の出発点であり、全所要時間に対する実モデル評価の代わりではない。

数値・期限・担当・引用・発言者帰属の決定論的照合と、背景・訂正・撤回・可読性の意味評価を分ける。Judgeのみで採用しない。重大な未根拠決定、担当/期限捏造、不正引用の新規発生は許容しない。

`tools/evaluation/fixtures/understanding-gold.json` に25の合成シナリオを追加。5/15/30/60/120/190分の時間軸は `gold_fixtures.load()` で発言単位に展開し、前半の公開決定・中盤の障害・最終撤回を跨区間で検証できる。架空の時間軸であり実音声はない。各重要事実は逐語引用・話者・実在するfixture segment IDに対応し、原文に存在することを自動確認する。実モデルの抽出成績はまだ計測していない。

## オフライン比較レポート

`python3 tools/evaluation/summary_report.py --baseline /external/before.json --candidate /external/after.json --output /external/new-report.json`。入力は [開発用README](../tools/evaluation/README.md) を参照。原文hash、facts/decisions/actionsのPrecision/Recall/F1、担当/期限/話者/引用、撤回、不正出典、重複を検査し、性能分布と同じcaseに表示する。語義・可読性・正当な追加事実の評価を文字列比較で置換しない。

未レビュー、mock/host時間、条件不一致、欠測、3回未満のcohortでは自動採用を止める。3回は最低収集条件であり統計的有意差の証明ではない。人手のリリース判断と公式評価は別途必要。実モデルの比較結果はまだない。

初回の統合結果は[2026-11-15統合検証](summary-performance/VALIDATION_2026_11_15.md)、以後の実装・残タスク・未検証事項は[現況一覧](summary-performance/STATUS.md)を参照。

## 実行中の入力変更を検出する

`run-quality-checks.py` は開始時と各群の前後に、App/Shared・tools/checks・tools/evaluation・tests配下のcode/fixtureと、Project.json等の設定を照合する。拡張子の範囲と件数は出力の `source-snapshot.json` に記録する。画像など全バイナリassetの同一性や、全依存環境の再現を証明するものではない。

内容のSHA256に加えinode/size/mtime/ctimeの指紋を持ち、同じ内容へ保存し直した場合もrun内の変更として扱う。読み取り中の変更・読取不能・symlinkのcode入力ではfail closed。記録するのは指紋と件数であり、ソース本文・APIキー・ユーザーのSQLite原文は出力しない。

変更時は `sourceChanged` / 非0終了にして、後続群を開始しない。子processのexit0も成功扱いに変更せず、実際のexitCodeと観測した指紋を残す。docsのメモや生成ログ/bytecodeは監視対象外。共有working treeから隔離したbuildそのものではなく、各群の前後の検証とSwift compilerのinput変更検出を併用する。

2026-11-15追加検証: runnerの9単体テスト成功。実repoの1,958入力を連続で照合して一致し、同じrunnerで実際のsummary-planning / summary-evaluationの2群成功。これは10群全てを新guardで再実行した結果ではない。直前のアプリ変更については[送信制御の検証記録](summary-performance/SUMMARY_REQUEST_SCHEDULING.md)を参照（9群と、途中失敗後のnext-generation再実行成功を別記）。モデル品質の得点は追加していない。

```sh
MEMORA_CHECK_TMPDIR=/external/scratch PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/checks -p test_quality_runner.py -v
python3 tools/checks/run-quality-checks.py --output-dir /external/new-frozen-input-checks
```

開発用SSDの `quality-source-guard-final.log` と `quality-source-guard-smoke/source-snapshot.json` / `summary.json` に今回の結果を保持した。通常の全10群実行にも同じguardが適用される。

## 保存済み音声の準備候補

[追加検証](summary-performance/AUDIO_PREPARATION_PIPELINE.md)は実WAV/AAC変換＋固定認識応答で逐次同等・先読みの重なり・失敗/熱/原本変更/キャンセルを確認する。ガード付き全10群のソース指紋も一致。これは実認識・実要約モデルの品質評価ではない。

確定区間の版管理も[追加検証](summary-performance/SETTLED_CHUNK_REVISIONS.md)。実SQLiteで旧形式/破損/変更/再開/失効を確認し、ガード付き全10群とE2E選択2件が成功。実認識・生成モデルの評価ではない。
