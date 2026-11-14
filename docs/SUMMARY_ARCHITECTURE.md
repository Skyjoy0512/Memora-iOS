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

開始時点 `183b1226` のコードから確認できた制約:

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
| 2 | 短縮ID・能力判定・低リスク処理 | 短縮ID済み。既存能力カタログへの統合とprovider保護は回帰検証済み。ジョブ単位の通信session再利用も無料検証済み。SSE off-mainも実行場所・通知順序を無料検証済み |
| 3 | 容量計画・並列・SoT候補 | A/Cの容量計画・推論から独立した並列は無料回帰検証済み。SoT候補は未実装 |
| 4 | 検証済み中間成果物・再利用 | 長文partのSQLite再利用と失効を実装・無料検証。全文を理解済みとする横断利用は継続 |
| 5 | 確定区間と音声処理の重なり | 未着手 |
| 6 | 総合検証 | 未着手 |

状態は検証後に更新する。実モデル検証のない候補と本番で採用する処理を区別する。

## 容量計画と実行

`SummaryTokenBudget` は共有ModelCapabilitiesの容量から、実際のsystem/profile/schema/記録metadata/話者対応のbyte上界、出力予約、framingと安全余白を引く。tokenizerが無い値はUTF-8 byte上界による計画値であり、課金tokenとして扱わない。unknownの32Kは既存のconservative profileの仮定であり、そのモデルの実上限を確認した値ではない。

`SummaryInputPartition` は全文が収まれば一括。収まらなければ発言単位、終端付近の話者変更/間隔、巨大な単一発言では文・空白境界を優先して分割する。文字・改行・記号を捨てず、各断片に同じ根拠IDを付ける。1文字さえ入らない場合や512区間を超える場合は送信せず失敗し、原文と既存要約を保持する。LLMによる議題分類を追加しない。

階層統合は同じ残り容量で計量し、既存の非縮小・上限・失敗検知を維持。独立する同階層groupもSummaryPartSchedulerで1/2 workerに制限して並列化し、結果は原順序で次段へ渡す。全段に同じ話者対応表を付ける。推論量を下げずに、レビュー済みの並列能力と低電力/thermal状態から1または2 workerを選択する。schedulerは1〜4をテストできるが、本番上限は2。途中失敗/429では他workerを止め、追加の区間・統合を送らない。自動再試行や別モデルへの再送は追加しない。

一括/部分抽出/統合はいずれも同じ既存prompt・parser・source検証・保存境界を使う。ユーザー編集した本文の正規化、タスク再作成、記録の一括再要約はしない。容量不足や検証失敗では既存の要約・履歴・原文を残す。SoT・録音中のLLM先行処理は完成扱いにしない。永続cacheの対応範囲は以下に限定する。

## 検証済み区間の再利用（Route D）

`SummaryArtifactCache` は既存LocalStoreのdocumentsに派生データ1行を保存し、DB/検索基盤を増やさない。Memoraの明示的なバックアップ・共有・検索索引の対象キーには追加しない。OSの端末バックアップでは、元の記録と同じSQLiteファイルの保護・保持方針に従う。

32区間・各256KiB・全体4MiB・24時間・LRU。JSON破損/出力hash不一致/期限切れ/保存失敗はcache missであり、既存記録の読み込みを失敗させない。起動時に現存ownerだけを残す。レコード・資料の原文/話者/取得範囲/所属/権限変更・削除、workspace/account変更、restoreで全cacheを保守的に破棄する。他レコードのcacheも破棄されるが、ユーザー本文やタスクは変更しない。

失効epochをMutexで同期的に変更し、actorでSQLite消去を直列化。消去前でも新しいleaseが失効済みデータを読めず、旧leaseは結果を再保存できない。遅延した消去は新世代の認可済み結果を保持する。ストア保護中はleaseのみ失効し、消去の書き込みを行わない。read/write・次の送信・最終保存の既存authorizeを維持し、scope/authorizeなしでは再利用しない。キーはowner/workspace/account/privacy/credential hash、全TranscriptSegment、provider/model/endpoint、容量/出力予約、推論モード、system/区間prompt/spec版。秘密・原文をキーや診断へ直接保存しない。

partNotesは従来の事実メモに加えて、任意の単一JSON notes/sourceReferencesを受理する。全参照IDと逐語引用を実際の当該断片まで照合できる完了応答だけをcacheする。旧proseも統合できるがcacheしない。壊れた宣言済みJSONは途中結果を最終生成へ渡さず失敗する。参照の検証は意味的な全事実の正しさ・網羅性を証明しない。中間メモを人物記憶や確定事実へ直接昇格しない。

長さ/表示順のみの変更はpartの抽出観点が変わらないので再利用する。異なる抽出focus・原文・話者・用語集・モデル・認証では元データから処理する。Single Passには追加の分析呼び出しを足さず、既存SummaryKnowledgeが全文を網羅すると仮定した再生成は行わない。失敗した長文の明示的再試行でも完了・検証済みpartだけを再利用し、不明な課金処理を自動再送しない。

## 共通prefix

Single Passのuser promptは記録metadata→原文→個別の構成/抽出契約。同一原文でlength/order/templateだけを変えた場合、原文までのprefixが同一であることをhostで検証。prompt cache対応は共有能力で表し、未確認のAPIパラメーターを送らない。自動prefix cacheを持つproviderへ適した配置だが、実ヒット率・cache write/read費用・速度は未測定。Anthropic等の明示TTL/外部保持期間は追加しない。
