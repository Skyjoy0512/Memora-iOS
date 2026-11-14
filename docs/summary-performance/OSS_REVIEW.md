# OSS・研究の確認記録

2026-11-14、[固定revision一覧](research-pins.json)。READMEだけでなく以下の実装を取得して確認した。更新日時はGitHub metadataであり、品質や安全性の保証ではない。

| 対象・一次資料 | 確認した実装 | Memoraでの方針 |
|---|---|---|
| [Skeleton-of-Thought](https://github.com/imagination-research/sot) | `sot/schedulers/outline_batch_scheduler.py`, router | 全体計画/抽出と原文を共有して並列展開するSwift候補を既存engine内に実装。入力課金・品質の実測gateが空なので通常は無効。 |
| [LlamaIndex](https://github.com/run-llama/llama_index) | `response_synthesizers/tree_summarize.py`, `indices/prompt_helper.py` | prompt/output余白を引いた再充填とasync統合を参考。無制限gatherや要約の無制限再圧縮は採らない。 |
| [LangChain](https://github.com/langchain-ai/langchain) | `combine_documents/{map_reduce,refine}.py`, core caches | モデル/chain分離と再利用の責務を参考。逐次Refineを高速化の既定経路にしない。 |
| [LLMLingua](https://github.com/microsoft/LLMLingua) | `llmlingua/prompt_compressor.py` | LLMLingua-2のtoken選別は意味損失を検証すべき別実験。原文の訂正・否定・条件を落とせないため採用・既定有効化しない。 |
| [TOON](https://github.com/toon-format/toon) | `benchmarks/results/token-efficiency.md`, benchmark README | 同じキーの繰返しを減らす観点を参考。独自結果をMemoraの実測に流用しない。複雑な引用/多行原文の新codecを先に導入せず、lossless短縮参照から始める。 |
| [Loqui](https://github.com/joaquingit1/loqui) | sidecar `postprocess/summary_mapreduce.py`, native helper/README | ローカル小窓で入力と出力が容量を共有する制約・確定後処理を参考。desktop sidecar・常駐プロセスはiOSへ持ち込まない。 |
| [Meet2Notes](https://github.com/estebanstifli/Meet2Notes) | `infrastructure/llm_context.py`, `docs/automatic-context-cache.md` | モデルごとの入力容量と再利用責務を参考。GGUF/Ollama探索・desktop自動起動をiOSへ移植しない。 |
| [J-MeetEval](https://github.com/nishika-inc/jmeeteval) | model, registry, checkers, evaluator, async client, tests | 開発専用に原本を固定導入。ルール5種とJudgeを分離。無断のJudge・再試行課金を禁止。 |
| [MeetingBank](https://aclanthology.org/2023.acl-long.906/) | 論文要旨・公開評価方法 | 長い会議と部分議事録の対応を参考に原文根拠付きgoldを準備する。データそのものは未導入。 |

J-MeetEvalはApache 2.0、他の8リポジトリ参照のうち上記7件はMIT（固定revisionのLICENSEを確認）。J-MeetEval以外はコードを配布物へコピーせずSwiftで責務に適した設計にする。LLMLinguaの学習モデル・TOONのTypeScript・LlamaIndex/LangChain等のPython依存、Electron/desktop sidecarを本番iOSへ追加しない。

J-MeetEvalのみ開発用Python環境を分離し、dependency lockを保存。上流の実行コードを自動ダウンロードして本番で実行する仕組みはない。通常CIはオフライン監査。Judge・生成の資格情報を本番アプリから読み出さない。脆弱性の完全監査や第三者OSSの将来の保守継続を保証するものではない。
