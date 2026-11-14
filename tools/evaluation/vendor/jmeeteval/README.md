# J-MeetEval

**日本語の会議タスクにおける指示追従性ベンチマーク**

長い会議の文字起こしを入力として与え、「議事録を作れ」といった要約タスクに対して、
モデルが**指定された形式・制約にどれだけ正確に従えるか**を測ります。

```
入力: 会議の文字起こし（中央値 9,072 文字）＋ 指示
      例) 数値は全角で統一すること / 決定事項のみを抽出すること /
          アクション項目には担当者と期限を必ず記載すること

出力: 指示ごとの 0/1 判定 → プロンプトレベル精度・指示レベル精度
```

## 目次

- [特徴](#特徴)
- [扱うタスク](#扱うタスク)
- [評価手順](#評価手順)
- [評価の仕組み](#評価の仕組み)
- [ベースライン結果](#ベースライン結果)
- [データセット](#データセット)
- [ライセンス](#ライセンス) / [引用](#引用)

**詳細ドキュメント**

| | |
|---|---|
| [RUN_GUIDE.md](RUN_GUIDE.md) | セットアップから実行までの手順、オプション、トラブルシュート |
| [docs/docker.md](docs/docker.md) | Docker / Docker Compose での実行 |
| [docs/results.md](docs/results.md) | ベースライン結果の詳細（カテゴリ別・サブ指示別） |
| [docs/instructions.md](docs/instructions.md) | 16カテゴリ・30指示キー（実装）の内容と例 |
| [docs/instruction_interactions.md](docs/instruction_interactions.md) | サブタイプ別の難易度と、指示の組み合わせによる劣化 |
| [docs/dataset.md](docs/dataset.md) | データセットの統計と構築方法 |
| [docs/data_format.md](docs/data_format.md) | データ形式・Python API・拡張方法 |
| [🤗 nishika-inc/jmeeteval](https://huggingface.co/datasets/nishika-inc/jmeeteval) | HuggingFace 上のデータセット |

## 特徴

- **入力が長文の会議文字起こし** — 3,015〜11,437 字（中央値 9,072 字）。分量比率・記載順序・
  表記の統一といった、文書全体にまたがる制約を評価できます。
- **1 プロンプトに複数の指示を同時に課す** — 1 件あたり平均 2.07 件（16 カテゴリ・25 指示キーを出題、27 キー定義中）。
  指示を 1 つずつ測る形式では見えない、指示どうしの干渉が観測できます。
- **判定は指示ごとの 0/1** — 段階評価ではないため、文章の巧拙と切り離して指示追従性だけを測れます。
- **ルールベースと LLM-as-a-Judge のハイブリッド** — 機械的に検証できる指示はルールで、
  「人物名を役職付きで統一する」「会社名を匿名化する」のように正規表現では判定できない指示は
  judge で判定します。判定理由はすべて保存されます。

## 扱うタスク

会議の文字起こしを渡し、議事録作成・要約・整形・匿名化といった出力を求めたうえで、
指示された形式・制約を守れているかを判定します。指示は次の 16 カテゴリです。

`output_constraint`（フィラー除去・句点除去・議事録のみ出力）/
`length_control`（文字数・文数・元文書比）/
`formatting`（箇条書き・セクション構造・Q&A形式・必須項目）/
`notation_rules`（人物表記の統一）/
`writing_style`（数値の全角半角・文体統一）/
`emphasis_rules`（強調タグ）/
`anonymization`（個人情報の匿名化）/
`structural_granularity`（トピック単位の段落化）/
`annotation`（冒頭注記・末尾注記）/
`viewpoint_spec`（特定観点へのフォーカス）/
`language_translation`（日本語要約・英訳）/
`template_filling`（テンプレート穴埋め）/
`json_output`（JSON 出力）/
`todo_rules`（アクション項目への担当者割当）/
`order_spec`（指定順序での並べ替え）/
`table_format`（Markdown 表出力）

各カテゴリの指示文と例は **[docs/instructions.md](docs/instructions.md)** を参照してください。

## 評価手順

```bash
# 1. 依存関係のインストール
uv sync

# 2. APIキーの設定
cp .env.example .env   # OPENAI_API_KEY を記入

# 3. 評価の実行（生成 → 採点 → レポート）
uv run python jmeet_eval_pipeline.py --model gpt-5-mini
```

`--output_dir` 配下に、生成応答・評価結果・サマリー・API使用量が出力されます。
まず動作確認したい場合は `--num_examples 2` を付けてください。

生成は OpenAI 互換エンドポイントであれば何でも使えます（vLLM / Ollama 等）。
`OPENAI_BASE_URL` を向け先に設定してください。

- **[docs/docker.md](docs/docker.md)** — Docker / Docker Compose での実行（GPU でローカルモデルを評価する場合）
- **[RUN_GUIDE.md](RUN_GUIDE.md)** — オプションの詳細、個別実行、トラブルシュート

## 評価の仕組み

**指示の判定** — 30 の指示キーを 28 個のチェッカーが判定します。うち 5 個がルールベース
（文字数、数字の全角半角、文数など機械的に検証できるもの）、23 個が LLM-as-a-Judge です。

**LLM judge** — 既定は `gpt-5-mini`（`LLM_JUDGE_MODEL` で変更可）。judge には temperature を指定せず、モデル既定に委ねます。
1 つの指示につき **3 回成功するまで実行（最大 5 試行）し、その平均**を取ります。
judge には 0 か 1 のみを返させ、それ以外の値はパースエラーとして再試行します。
3 回揃わなかった場合は**評価不可**として、スコアではなく母数から除外します。
judge モデルを変えるとスコアが変わるため、結果を比較する際は judge を揃えてください。
被評価モデルの出力は `<response>` タグで区切り、その中に評価者への指示（スコアの指定など）が
含まれていても無視するよう judge に指示しています。ただし LLM-as-a-Judge の性質上、
プロンプトインジェクションや judge の癖によるバイアスを完全には排除できません。

**指標** — 精度計算時は平均スコア 0.5 以上（3 回中 2 回以上パス）を「指示遵守」として二値化します。

| 指標 | 定義 |
|---|---|
| `prompt_level_strict_accuracy` | 1 件のプロンプトで**全指示**を満たせた割合 |
| `instruction_level_strict_accuracy` | 個別指示単位のパス率 |
| `{category}_accuracy` | カテゴリ別のパス率 |

## ベースライン結果

同梱の合成データセット 197 件を、judge に `gpt-5-mini`（1指示につき
3回投票の多数決）を用いて評価した結果です。

| モデル | プロンプトレベル精度 | 指示レベル精度 | 応答長 中央値 |
|---|---:|---:|---:|
| `google/gemma-4-E4B-it` | 69.0% | **83.3%** | 1,985 字 |
| `Qwen/Qwen3-VL-8B-Thinking` | 65.5% | **80.6%** | 1,340 字 |
| `google/gemma-4-E2B-it` | 64.0% | **80.6%** | 2,081 字 |
| `Qwen/Qwen3-8B` | 57.4% | **76.0%** | 1,262 字 |
| `tokyotech-llm/Qwen3-Swallow-8B-RL-v0.2` | 55.6% | **74.3%** | 1,650 字 |
| `nvidia/NVIDIA-Nemotron-Nano-9B-v2-Japanese` | 54.8% | **73.3%** | 776 字 |
| `Qwen/Qwen3.5-4B` | 52.0% | **72.1%** | 1,302 字 |

**測定条件**: データ `data/transcripts.jsonl`（197会議 / 408指示 / 16カテゴリ、
`md5 85a5e8bdc76f`）、`data/instructions.jsonl`（`md5 891d1a399e31`）。生成は temperature 0.7、
判定は `gpt-5-mini` で 1 指示につき 3 回投票の多数決。測定日 2026-07-20。
reasoning 系（gpt-5・o 系）は temperature 非対応のためモデル既定に委ね、長さは reasoning 側トークンで
制御します。各スコアは単一実行の値で、指示単位ではおおむね ±20% 程度ぶれ得ます。

カテゴリ別・サブ指示別の内訳は **[docs/results.md](docs/results.md)**、
サブタイプ別の難易度差と指示の組み合わせによる劣化は
**[docs/instruction_interactions.md](docs/instruction_interactions.md)** にまとめています。

判定理由は評価結果ファイル（`--output_dir` 配下の JSON）にすべて保存されます。

## データセット

同梱の `data/transcripts.jsonl` は **197 件の合成（生成）会議文字起こし**です。
HuggingFace でも配布しています: **[nishika-inc/jmeeteval](https://huggingface.co/datasets/nishika-inc/jmeeteval)**

**実在の会議の録音・文字起こしではありません。** 実在の個人・組織の機密情報を含みません。
**`Qwen/Qwen3-235B-A22B-Instruct-2507`** を用いて GENIAC 期間中に生成しました。生成時に
与えたのは業界名・会議テーマ・会議の進行パターンのみで、実会議の文字起こし本文は入力していません。

実データの代替として使えるよう、実会議データの文字数分布に動的計画法でマッチングさせて
選抜しており、文字数の中央値は実データ（9,191 字）とほぼ一致する 9,072 字です。

統計・構築方法は **[docs/dataset.md](docs/dataset.md)**、
データ形式・Python API は **[docs/data_format.md](docs/data_format.md)** を参照してください。

## ライセンス

本リポジトリは **Apache License 2.0** で公開しています。全文は [LICENSE](LICENSE) を参照してください。
同梱のデータセットおよび HuggingFace 上のデータセットも同じ Apache License 2.0 です。

本プロジェクトは [Google IFEval](https://github.com/google-research/google-research/tree/master/instruction_following_eval)（Apache License 2.0）の設計を参考にしています。帰属表示は [NOTICE](NOTICE) に記載しています。

## 引用

```bibtex
@misc{jmeeteval,
  title  = {J-MeetEval: A Japanese Instruction-Following Benchmark for Meeting Tasks},
  author = {Nishika, Inc.},
  year   = {2026},
  howpublished = {\url{https://huggingface.co/datasets/nishika-inc/jmeeteval}}
}
```
