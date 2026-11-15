# 要約高速化・評価基盤の統合検証（2026-11-15）

対象は `183b1226` 以降、実装最終レビュー `dc82f7f4`。実モデル評価は利用者指定により実施しない。今回の開発結果は、アプリの実装・無料回帰・合成入力での構造的改善の検証であり、60秒/30秒/終了後10〜20秒の達成報告ではない。

## 実装と採用範囲

| Phase | 結果 | 制限 |
|---|---|---|
| 0 調査・診断 | request別の数値usage/timing/outcomeと既存STT/summary/save spanを分離 | 実APIベースライン未取得 |
| 1 評価基盤 | 固定J-MeetEval、独自gold、公式ルール、比較レポート、通常無料回帰 | 生成/Judge未実行。課金上限付きLevel 2/3 runnerは未実装 |
| 2 低リスク改善 | 短縮ID、能力共通化、容量計画、job内HTTP再利用、SSE/JSON解析off-main | モデル別の実token/速度・実TCP再利用は未測定 |
| 3 適応経路 | A全文、C階層、D検証済みpart再利用、E端末内を既存経路へ統合 | B並列文章生成は候補実装のみ。採用gateは空で閉鎖 |
| 4 再利用基盤 | 既存SQLiteへの有界part cache、scope/失効、根拠ID/引用検証 | 全文の完全な意味理解cacheではない。人物記憶へ自動昇格しない |
| 5 音声先行処理 | 既存確定checkpointとライブ表示経路を調査 | 新たな並行音声処理・録音中クラウド分析は未実装・未採用 |
| 6 統合検証 | 最終コードの無料10群成功、iOSビルド成功 | 実モデル・実機計測は未実施。UI結果は以下 |

プロバイダー仕様と共通能力の正本は既存ModelCapabilities。unknownはunknownのまま扱う。カスタムendpointに専用パラメーターを推測送信しない。ユーザー選択モデル/推論設定を保持する。DeepSeek/OpenAI/OpenRouter/互換APIは既存互換経路、AnthropicはMessages、Geminiは既存OpenAI互換経路、Appleは既存Foundation Modelsである。新たなGeminiネイティブAPI、ローカルLLM、Memoraサーバーを実装済みとは扱わない。[詳細能力表](../MODEL_CAPABILITY_MATRIX.md)。

## ボトルネックについて確認できたこと

旧固定文字数閾値は、モデル容量に収まる入力にも複数の部分生成と最終生成を計画した。UUIDを発言ごとに反復する入力、main上のストリーム解析、同じjobで接続を作り直す経路、キャッシュhitごとの全量SQLite書き戻しもコード/host検証で確認・修正した。これらが利用者環境の120秒超のうち何秒を占めたかは未計測。逐次のモデル出力・推論・混雑の寄与も不明である。

| 同じ合成入力の比較 | 変更前 | 変更後 | 実際に確認した範囲 |
|---|---:|---:|---|
| 1,000発言のwire入力 | 199,999 bytes | 151,139 bytes | 24.43%減。本文/Unicode/順序/話者/UUID往復は保持。token比率ではない |
| 1,000発言、従来表現112,889文字の容量計画 | 3 part + final = 4 request | 1 request | 実オーケストレーター+通信mock。全文の送信を確認 |
| 大きな同一原文の長さ/順序変更後の再生成 | 4 part + final = 5 request | cache 4 part + final 1 request | 検証済み部分のみ再利用。実料金/意味品質は未評価 |
| cache 10 hit と変更なしowner cleanup | hitごと全量書戻し | 追加write 0 | 別SQLite接続のdata_version不変を検証 |
| 60分の実API要約時間 | 利用者報告120秒超 | 不明 | 同条件実測なし |
| 実API費用・token・TTFT・推論時間・P50/P95 | 不明 | 不明 | 未計測を0や推定値で埋めない |
| 実モデルの事実/決定/TODO Precision・Recall・F1 | 不明 | 不明 | fixtureの成績で代用しない |
| J-MeetEval公式総合スコア | 不明 | 不明 | Judge未実行。ルール部分を総合点にしない |

## 品質と整合性

短縮IDはsnapshot内の順番に対応し、構造化参照だけを元UUIDへ復元する。原文や手編集Markdownを置換しない。引用は実際に送った区間に照合し、生成factのspeakerIDsも引用元segmentに限定する。存在する別話者を誤って紐付けた場合は除去し、confirmedをuncertainへ下げる。fence内の不完全notes JSONも完了として統合しない。決定・担当者・期限の意味的な正しさを決定論的検査だけで保証するものではない。

cacheは24時間・32件・4MiB、単一256KiBまで。原文全field/話者/用語/モデル/endpoint/推論/仕様/owner/workspace/account/privacy/認証revisionを反映する。鍵そのものは保存しない。削除/権限/restore時のlease失効は同期し、古いworker・起動cleanupの書戻し/削除を防ぐ。hitのLRU touchはRAMで管理し、次のwriteに反映する。再起動直後のLRUは最後の永続化時点になる。cache非存在時は追加の全record比較を避け、分析開始時に存在flagを立てて失効を漏らさない。

保存本文・履歴・完了タスク・ユーザー編集・音声を起動時に書換えない。新規DB/検索基盤を追加せず、既存SummaryKnowledge/原文/RAGを維持。部分メモを確定した人物記憶に変換しない。旧record、破損enrichment、backup/restore、権限、再生成競合は既存host回帰を利用した。

## 無料テストと再現

最終アプリコード `dc82f7f4` と同じ内容で `run-quality-checks.py` の10群すべて成功:
summary-planning / summary-evaluation / next-generation / design-refresh / background-summary / summary-reliability / adaptive-summary / adaptive-summary-quality / composer-layout / optimization。

10群には実productionコードを使う能力判定・全原文分割・1/2/3/4並列・到着逆転・429 fail-stop・キャンセル・出典・失効・SQL・保存競合・既存UI等を含む。仮想時計/通信mockの時間をAPI性能と呼ばない。表示256イベントを超える300 requestの数値保持、4,097件で欠測を明示する上限も検証した。

J-MeetEval上流107テスト成功（ネットワーク遮断、固定版）。独自評価器の開発環境全11単体テスト成功、通常依存なし経路8件成功。独自25 goldケースと5/15/30/60/120/190分のtimelineを用意した。これは評価器とfixtureの検証であり、生成モデルの品質評価ではない。

実行ログは開発用SSD `/Volumes/WorkspaceSSD/Development/Agents/MemoraSummaryPerformanceValidation` に保持。最終10群は `quality-2026-11-15-final/summary.json` と各群のlog。iOS preview `2026-11-15T06-13-40-f32d286a.log`、E2E用同内容build `2026-11-15T06-17-37-af24be3c.log` は成功、既存11警告。配信用の最終preview `2026-11-15T09-22-12-19c18d0d.log` も成功（既存11警告）し、Bitrigのpreviewを更新した。Project.json/配布targetへ評価コードを追加していない。

```sh
python3 tools/checks/run-quality-checks.py --output-dir /external/new-summary-checks
python3 tools/checks/run-summary-evaluation-checks.py
# 固定uv環境の用意と公式ルール実行は JMEETEVAL_INTEGRATION.md 参照
python3 tools/evaluation/summary_report.py --baseline /external/baseline.json --candidate /external/candidate.json --output /external/new-report.json
bitrig preview -platform iOS
```

比較入力には同一原文/指示hash、実model/provider/endpoint/推論/出力予算、commit、dataset/prompt版、cold/warm、並列数と複数回測定を保存する。未知料金・欠測・人手未レビュー・重大誤りは採用を止める。reportが成功しても `automaticAdoptionAllowed` はfalseであり、実装gateを自動解除しない。

## シミュレーターUI確認

最終buildと同じアプリコードのiPhone 18 Proで `summary-reading-accessibility.e2e.ts` が成功（56.07秒はUI操作の時間）。normalからaccessibility-largeへ本文高が増加し、402pt幅の収まり、dark、表の最終列への横スクロール、チェックリスト、長文末尾とAsk AI欄、保存本文/原文の不変を確認した。run `01a1dc8e-dc59-71d2-bb4f-eda25dd5c7fb`、`.e2e/summary-performance-narrow-focused/report.json`。modelTokens=0、maxModelCallsInStep=0。

初回の狭幅実行はOSの「Memoraで開きますか」確認で停止したため、fresh install後に残るalertとdeep link承認をtest helperで扱うよう修正。次の試行は空のmultiline editorへの入力/read-back・一文字ずつ入力の期限で失敗した。入力開始位置と一括keyboard入力を使い、最終成功を確認した。この途中の入力方式を用いたPro Maxの再実行2件も準備で失敗しており、最終の2件成功と区別して保持する。過去の失敗traceは削除しない。画面本体や合否の期待値を緩めていない。

同じ最終アプリbuildのiPhone 18 Pro Maxで、閲覧/編集/出典/task/copy/share/historyの1件（162.85秒）と、保存失敗の原文/draft復旧1件（90.07秒）が成功。run `01a1dc90-165a-7665-ae3f-5eea923f54b3`、`.e2e/summary-performance-supported-confirmed/report.json`。2選択・2成功、modelTokens=0、maxModelCallsInStep=0。狭幅と合計3件の成功であり、全138 UIテストを実行した意味ではない。UIテスト追加commitは `d84dcf42`。数値の要約は [results JSON](results-2026-11-15.json)。

先行run `.e2e/summary-performance-final/report.json` は3選択・2成功・1失敗。要約の引用→文字起こし（音声なし）、task追加/完了、抽出/本文編集、copy/share、履歴復元後の完了task保持、table inline編集/keyboardと、保存失敗後の原文/draft保持は成功。PNG書込み失敗のtestだけは `summary.poster.inline` に到達せず失敗した。この入口は基準commitでも `FeatureFlags.isInlineSummaryPosterEnabled=false` のため表示されない。フラグを変更せず、PNG復旧UIは未検証・全E2E成功とは扱わない。

手動でもPNGを確認した。以下は**合成した保存済みfixtureの表示**であり、LLM生成の改善後サンプルではない。既存のモノトーン、自然な余白、native操作、横スクロール、keyboard上の編集を保持する。

| 通常 / dark | 狭幅・拡大文字 | 表 / keyboard |
|---|---|---|
| [通常](screenshots/summary-light.png) / [dark](screenshots/summary-dark.png) | [拡大文字dark](screenshots/summary-narrow-large-dark.png) | [横スクロール](screenshots/summary-narrow-table.png) / [table編集](screenshots/summary-table-keyboard.png) |

UIテストは専用simulatorにfresh installし、UI作成したUUID markerと空のrecord集合を確認したDBだけをseedする。Bitrig preview/実機のデータはseedしない。新config `e2e.summary-performance.config.ts` は既存configを継承してdeviceをProに限定する。本番UI・Project.json・依存packageは変更しない。実行時は評価用API環境変数を除去し、agent stepを含まない選択だけ実行した。

```sh
# bitrig build -destination 'platform=iOS Simulator' のapps[0]を指定する。
# 評価用APIキーを設定しないshellで実行。通常の全e2eは別のagent testを含む。
MEMORA_E2E_APP_PATH=/absolute/path/to/Memora.app E2E_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1 npx --no-install e2e run tests/summary-reading-accessibility.e2e.ts --config e2e.summary-performance.config.ts --workers 1 --retries 0 --no-cache --output .e2e/new-summary-narrow
MEMORA_E2E_APP_PATH=/absolute/path/to/Memora.app E2E_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1 npx --no-install e2e run tests/adaptive-structured-summary.e2e.ts tests/summary-recovery.e2e.ts --grep 'adaptive reading|failed transcript saves' --workers 1 --retries 0 --no-cache --output .e2e/new-summary-supported
```

## OSSと採用判断

[実コード調査・revision/license記録](OSS_REVIEW.md)を保持。SoTの共有計画と有界並列は候補へ、LlamaIndex/LangChainの階層統合・context packing・非同期の設計は既存Swiftへ反映。7つの参考実装を丸ごと依存追加しない。LLMLinguaの情報損失圧縮、TOONへの一括変更、desktop録音実装の移植は未採用。Loqui/Meet2Notesは確定区間/容量ルートの参考、MeetingBankは長時間評価方法の参考でデータは未導入。J-MeetEvalのみ開発専用に固定導入し、Apache LICENSE/NOTICEと上流基準を維持する。

## 残存課題・フォールバック

- Bの候補は実際の品質/費用/速度ゲートを通していない。通常は既存A/Cへ進み、追加planを発行しない。B候補でAPI送信後の失敗を全再生成して課金を増やさない。
- Dは検証できる長文partに限定。cache miss/破損/失効は原文経路へ戻す。原文を網羅しない既存knowledgeだけで全文の再分析を省略しない。
- 並列上限は能力/低電力/thermalに応じ保守的に決定（通常最大2、unknown等1）。全job横断RPM/TPM推定、Retry-After学習、6並列以上の実測は未実装/未実施。429はfail-stopし、自動課金retryを足さない。
- providerの明示cache TTL/保持延長は追加しない。cache write料金/実ヒット率、未知モデルtokenizer/価格は未確認。
- ライブ文字起こしは表示用で欠落を許すqueueがあり、完全な確定原文として再利用できない。保存済みSTTのcheckpointは維持するが、単一staging音声fileを並列exportで上書きしないための二重buffer、確定ID/話者整合、実機CPU/発熱/録音drop検証が先に必要。Phase 5は未実装。
- Level 2/3の生成/Judge runner、独立資格情報・実費上限の制御は将来作業。今回は実モデルを実行しないという利用者指定を維持する。
- 実機録音、実サービス認証、Jinba品質、実機電池/発熱/メモリ/スクロールFPS、VoiceOver/日本語IMEの実操作は未検証のまま。新しい外部書込み/サービスdeployは行っていない。

## 実装コミット

62d0f166 評価基盤、b3b675ee 短縮ID、2e03d71a 容量/能力計画、c425146f HTTP scope、8d24a93f stream off-main、6ef48197 scoped cache、da1167e1 階層並列/prefix、23f22d25 数値診断/比較レポート、bb226f5b gate付きSoT候補、dc82f7f4 cache I/O/根拠レビュー。

主要ファイルは MeetingSummarizer / MeetingSummaryInput / SummarySourceIndex / SummaryTokenBudget / SummaryInputPartition / ModelCapabilityRegistry / SummaryProviderAdapter / SummaryGenerationPolicy / SummaryPartScheduler / SummaryNoteHierarchy / CloudHTTPTransport / CloudTurnStreaming / CloudTurnStreamReader / SummaryDiagnostics / SummaryArtifactCache / MemoraModel+SummaryArtifacts / SummaryCompositionPlan / MeetingSummarizer+ParallelComposition / SummaryOptimizationGate と tools/evaluation / tools/checks。既存の要約エンジンを拡張し、別エンジンを重複新設していない。
