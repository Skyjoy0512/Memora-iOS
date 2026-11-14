# 要約推論基盤の実装記録

2026-11-14開始。基準コミット: `183b1226`（適応型要約導入後）。本書は以前の [適応型要約設計](adaptive-summary/IMPLEMENTATION.md) を置き換えず、実行計画・性能・再利用の責務を補足する。

## 維持する境界

- `MeetingSummarizer` を唯一の要約オーケストレーターとして拡張する。
- 通常の要約は全原文を1回の呼び出しで処理する。モデル、推論設定、出力の詳しさを高速化のために変更しない。
- 構造化情報は既存の `SummaryKnowledge` / `TemplateSummary`、永続化はSQLite。原文とユーザー編集・タスク完了状態は正本のまま。
- 権限・入力fingerprint・workspaceを送信前と保存前に再確認する既存の境界を維持する。
- プロバイダー未提供の使用量・料金・推論時間は不明。推定入力容量を実測トークン数として扱わない。
- 実モデル評価は利用者の指定により実施しない。新しい複数呼び出し経路を品質検証なしに通常経路へ昇格させない。

## Phase 0: 調査

現行コードから確認できた制約:

1. `MeetingSummarizer`: 60,000文字以内を一括、40,000文字単位で長文分割。モデル容量に関係なく同じ分岐。
2. `SummaryGenerationPolicy`: 高速モードのレビュー済みDeepSeekのみ2並列。他は逐次。推論量と並列数が結び付いている。
3. `SummaryNoteHierarchy`: 最大8段、順番に統合。原文への参照は保持する指示があるが、統合中に原文を再確認するAPIはない。
4. `MeetingSummaryInput.cloudLine`: 毎発言にUUID全体を送信。短縮IDの対応表は未実装。
5. `CloudTurnStreaming`: HTTPごとにephemeral URLSessionを生成・破棄。
6. SSE本文バッファは既にappend方式、UI通知100ms・activity1秒に抑制済み。ここを重複実装しない。
7. `SummaryDiagnostics`: requestごとの推論開始・TTFT・最終本文・usage・parse/saveイベントがある。キャッシュcounterと機械可読集計は不足。
8. `AudioProcessingDiagnostics`: 取り込み、STT、話者処理、要約の実時間spanが既存。別の時系列計測器を増やさない。
9. Foundation Modelsは小さい区間のguided generation。ローカルLLM、Memora Intelligence専用サーバーは未接続。Geminiは既存のOpenAI互換エンドポイントを利用する。

これらは実装上の制約であり、利用者が報告した120秒の内訳を確定するものではない。

## 実装順と証跡

| Phase | 作業 | 状態 |
|---|---|---|
| 0 | 現行パイプラインとOSS調査 | 調査済み、実APIベースラインは未測定 |
| 1 | 固定版J-MeetEval・独自評価・性能集計 | 固定データ監査・公式checker/単体テスト成功。長文gold追加と計測連携は継続 |
| 2 | 短縮ID・能力判定・低リスク処理 | 未着手 |
| 3 | 容量計画・並列・SoT候補 | 未着手 |
| 4 | 検証済み中間成果物・再利用 | 未着手 |
| 5 | 確定区間と音声処理の重なり | 未着手 |
| 6 | 総合検証 | 未着手 |

状態は検証後に更新する。実モデル検証のない候補と本番で採用する処理を区別する。
