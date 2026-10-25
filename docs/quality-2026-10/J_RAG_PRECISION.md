# 根拠候補の関連性改善（2026-10-26）

P1: 本文のbigramを1つ共有するだけの資料や、最大scoreの40%程度の弱い一致がAIのcontextに混入していた。検索権限は正しかったが、正しいスコープだけでは正しい根拠にならない。

## 実装

- FTS候補の再ranking後の閾値を2/3へ。ただし明示的な複数話題では、上位が持たないquery語を補う候補も保持する。閾値変更だけの初回検証では複数資料のRecall低下を発見したため、この補完を加えて再検証した。assertionは緩めていない。
- 同一のsource/page/time/text chunkを重複送信しない。異なるsourceやpageを勝手に統合しない。
- 単独の数字anchorはtoken全体で照合。50を150の一部として使わず、正しい桁区切りと全角を正規化する。複数の数値・複数話題は単純ANDで落とさない。
- 英語だけの質問は、偶然一致した2文字でなく少なくとも1つの単語全体が必要。明示的なselected source/overview/follow-upは既存の範囲付きcontextを維持。
- project/allowed targetによるfilterが先。index更新/削除/失効・workspace snapshot・送信直前の権限検査を弱めない。外部API/embedding/reranker/依存追加なし。

## 同一の拡張fixtureで比較

Before=`cb23b3d`、After=本変更。合成日本語corpusを12→27問へ拡張。医療条件・商談の承認否定・日常・英語識別子・複数根拠・数値部分一致・無回答を追加。正解ラベルは採点器と分離し、元のassertionを維持。すべての送信excerpt/pageが許可された元資料内にあることもassert。

| 指標 | Before | After |
| --- | ---: | ---: |
| hit@1（回答可能22問） | 22/22 | 22/22 |
| Recall@3 / MRR | 1.000 / 1.000 | 1.000 / 1.000 |
| Precision@3（分母は固定3、回答可能問の平均） | 0.379 | 0.379 |
| 無関係な送信source数 / 全送信source数 | 0.519 | 0.167 |
| 無根拠質問の棄権 | 1/5 | 5/5 |
| ホストp50/p95/max (ms、同一fixture各1回の例) | 0.46/10.57/12.75 | 0.58/4.21/16.48 |

元の12問だけではBefore=0.500、初回閾値変更After=0.188。これは27問の数値と混同しない。最終実装の全suite再測定はCに記録する。レイテンシは起動index構築と温キャッシュが混在するため、上表から速度向上を主張しない。

再実行: `python3 -B tools/checks/run-project-search-quality.py --baseline-ref cb23b3d` と引数なし。Beforeは測定専用で、旧実装が新しい棄権gateをPassしたとは扱わない。現行はすべてのgateを実行する。`run-optimization-checks.py`に含むProjectContextChecksでも重複・follow-up・1500/1,500/全角・50不一致を検査。

## 制限

関連性の改善はこの小規模corpusでのみ確認。なお16.7%の混入があり、topic検出や数値anchorは語彙ヒューリスティックで、意味・単位換算・否定の論理・照応を証明しない。英語の言い換えや複雑な複数質問で棄権しすぎる可能性が残る。例題の100%を一般利用へ拡張せず、実質問の匿名化評価・holdout・LLM回答の引用一致は未検証。秘密の原文を評価ログに追加しない。
