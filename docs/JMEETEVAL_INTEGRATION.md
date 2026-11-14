# J-MeetEval（開発・テスト専用）

[上流コード](https://github.com/nishika-inc/jmeeteval) `25365d48d1a4d685ed5b7dc62037ab2c95ae64f8` と [データ](https://huggingface.co/datasets/nishika-inc/jmeeteval) `6d3fc778e8ab2572ac52e79ae1dbd052fdc9a243` を固定した。197件・16カテゴリ。GitHub版とHugging Face版のJSONLがbyte単位で一致することも確認した。

`tools/evaluation/vendor/jmeeteval` のApache 2.0 LICENSE / NOTICEと著作権表示を保持。`MANIFEST.json`で全ファイルのSHA256を検証する。上流チェッカーの判定式・閾値・プロンプトを変更しない。本番ターゲットのsourcesはApp/Shared等に限定され、toolsは含まれない。Pythonやデータセットを配布バイナリへ追加しない。

## 無料実行

```sh
# 環境とcacheの保存先は開発用SSDなどの外部ディレクトリを指定する
UV_CACHE_DIR=/path/to/cache UV_PROJECT_ENVIRONMENT=/path/to/venv uv sync --locked --project tools/evaluation
/path/to/venv/bin/python -m unittest discover -s tools/evaluation/tests -v
python3 tools/evaluation/jmeeteval_offline.py --output /path/to/new-audit.json
/path/to/venv/bin/python tools/evaluation/jmeeteval_offline.py --responses /path/to/responses.jsonl --output /path/to/new-rules.json
```

応答ファイルは1行 `{"id":"s001","response":"本番相当パイプラインの出力"}`。指示の結合は上流のinstruction_keysの順序を守り、生成時はカスタムテンプレートの明示指示として渡す。専用のスコア対策生成器を作らない。評価への入力は合成・許諾データと保存済み応答のみ。

通常実行ではdotenv読み込みを無効にし、socket通信を遮断する。5種類の公式ルールチェッカーだけを実行し、残りのLLMチェッカーは `notEvaluated` / null。部分スコアを公式総合スコアと呼ばない。監査だけでは要約品質の合否を出さない。出力は既存ファイルを上書きしない。

## 実モデル評価の境界

今回は利用者の指定により生成・Judgeとも実行しない。197件の実モデルスコア、モデル間比較、速度・費用は未検証。

上流はJudgeを複数回実行し、失敗時の再試行も持つ。そのまま通常CIから呼ばない。Level 2/3の実行には独立した評価用資格情報、明示的なモデル・エンドポイント、リクエスト上限、入力/出力/推論を含む費用上限が必要。実際の請求上限を保証できない未知モデルでは課金ランナーを有効にしない。通常CIはキー・ユーザー原文・BYOKキーチェーンを参照しない。
