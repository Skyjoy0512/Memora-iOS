# 35シナリオと検証の対応

全35件に原文と期待する事実を定義した。27件は手作業の抽出結果を実際の新旧Swift builderへ同じ入力として渡す。残る8件は状態を扱う本番メソッドのホスト検証へ対応する。fixtureを作っただけでLLMの理解・抽出品質を合格とはしていない。

| # | シナリオ | 実施した検証と限界 |
| --- | --- | --- |
| 1 | 決定のない会議 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 2 | 行動のない会議 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 3 | 定例会議 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 4 | 担当未言及 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 5 | 期限未言及 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 6 | 明示的に担当保留 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 7 | 経営数値 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 8 | 意見の対立 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 9 | 方針変更 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 10 | 複数テーマ | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 11 | 短時間会議 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 12 | ブレスト | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 13 | 商談 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 14 | 1on1 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 15 | 日常会話 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 16 | 講義 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 17 | YouTube | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 18 | Webニュース | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 19 | 技術解説 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 20 | PDF資料 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 21 | 低品質文字起こし | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 22 | 複数話者 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 23 | 話者不明 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 24 | 長時間会議 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 74,028文字・65分相当の原文を収録。実LLMによる分割統合は未実行。 |
| 25 | 原文編集中 | SummaryEditingChecks / BackgroundSummaryExecutionChecks: 保存競合・開始後の編集を拒否。 |
| 26 | 本文編集済み | SummaryEditingChecks / SummaryKnowledgeEditChecks: 本文draft、抽出編集、履歴不変。 |
| 27 | 旧要約データ | AdaptiveSummaryKnowledgeChecks: 旧TemplateSummaryと壊れた任意抽出の復号。 |
| 28 | 固定フォーマット | SummaryPromptChecks / SummaryLayoutChecks: 明示カスタム形式は適応型清掃の対象外。端末内の実出力は未検証。 |
| 29 | 不完全JSON | AdaptiveSummaryKnowledgeChecks / LongSummaryChecks: 切断JSONと不完全ストリームを確定しない。 |
| 30 | 外部資料の命令 | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 プロンプトの非信頼資料ルールは検査したが、実モデルの攻撃耐性は未検証。 |
| 31 | 明示的な問題なし | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
| 32 | 完了後の再要約 | BackgroundSummaryExecutionChecks: 完了・担当・メモを保持。UIでも履歴復元後の完了保持を検証。 |
| 33 | 根拠の失効 | AdaptiveSummaryKnowledgeChecks / SummaryReadingChecks: 原文fingerprintとID/引用の再検証。 |
| 34 | 保存失敗と復旧 | BackgroundSummaryExecutionChecks / SummaryKnowledgeEditChecks: 実SQLite rollback/reopen、中断・再試行。OS強制終了を全地点で再現した検証ではない。 |
| 35 | 複数用途の組合せ | 同一のprepared digestで期待事実・空欄節・生成時清掃の冪等性を検証。モデルの抽出自体は未検証。 |
