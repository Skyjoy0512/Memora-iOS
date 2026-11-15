# 共通AI処理改善の実装・検証報告

全依頼を完了扱いにはしない。原文に対する引用一致を越えた意味的品質、モデル別tokenizer、
native pipeline全方式の実モデル評価runner、人物/長期記憶等への追加consumerが残る。
実装詳細と途中失敗は[IMPLEMENTATION.md](IMPLEMENTATION.md)、現在のロードマップは
[STATUS.md](../summary-performance/STATUS.md)を参照。

1. **実装内容**: 構造化partの受理ゲート、所有者/part単位cache失効、既存SQLiteの変更検知と
   RAM再利用、共有API admission、Knowledgeの読み取り時根拠再検証、SoTの実plan容量判定、
   明示許可・専用資格情報・外部spend guard必須のraw request評価runner。
   新規cloud providerのDeepSeek既定と旧OpenAI明示設定の移行保護。
2. **アーキテクチャ**: 既存のAdapter/抽出 → MeetingSummaryInput/TranscriptSegment/SummarySourceIndex →
   既存planner/MeetingSummarizer → SummaryKnowledge → 本文/Ask AI/Project検索を維持。
   新しい要約engine、DB、UIは追加しない。ライブSTT/録音中のAI分析は接続しない。
3. **変更ファイル**: 各commitの`git show --stat`が正本。主要変更はMeetingSummarizer、
   SummaryPartArtifact、SummaryArtifactCache/Identity、MemoraModel+SummaryArtifacts、LocalStore、
   SummaryRequestAdmission/GenerationPolicy、CloudHTTPTransport/CloudTurnStreaming/CloudAIService/
   CloudAgentSession、AIEngineService、agent/research/record/project/resident/grounded/図解/Web調査認可接続、Meeting+SummaryContent、
   MemoraModel+AI、SummaryCompositionPlan/ParallelComposition、tools/evaluationと対応test。
4. **修正した不具合**: 引用不正partの最終統合混入、誤型/欠損JSONの自由記述へのfallback、
   一レコード変更による無関係cache失効、毎hitの全量decode、失効worker書込、SoT planの二重予約、
   引用元と異なるspeaker IDの再利用、発言者であるだけの担当認定、要約以外の共有admission迂回。
5. **差分レビュー**: 送信前の再認可、permit解放、優先度aging、credential/endpoint分離、
   429/待機/容量/期限のfail-stop、owner leaseと消去順序、cache identityの全文依存除去を確認。
   permission失効後の編集で旧cacheが復活しない追加回帰を実施。意味的含意を証明したとは扱わない。
6. **既存機能への影響**: UI・navigation・capture・STT・確定区間revision・保存/履歴/完了taskの
   確定処理は維持。BYOKの選択model/endpoint/reasoning/出力予算を最適化のために変更しない。
   不正partは保存を完了せず、既存の失敗/再試行経路へ戻す。旧自由記述はuncached互換を維持。
7. **実行したテスト**: production Swift host checks、実SQLite、HTTP/SSE/JSON fixture、
   Python J-MeetEval/gold/metrics/report/runner、iOS Preview、限定agent-free UI E2E。
   Project.jsonにはXcode test targetが無く、bitrig testはexit78。host testsで代替する。
8. **成否**: 最終コードの10群は10成功/0失敗、source指紋は全群で不変。
   [検証メタデータ](VALIDATION.json)と[全138 UIケースの状態/試行履歴](UI_TEST_STATUS.json)を参照。
   UIの最新結果は3成功/0失敗/135未実行。最終UI実行もsource不変、agent model tokensは0。
   初回10群のresident fixture署名不一致、UIの旧文言/前提不足/識別子継承による失敗は履歴に保持。
   appのUIや期待する保存/非生成の条件は緩めず、明示provider/詳細設定の準備と現在のnative要素へ
   testを合わせた。途中のコンパイル失敗や実行中編集検知を成功と混ぜない。
9. **実測した改善**: mock inference + production orchestrationのrequest数は初回5 → 詳細度/順序変更1 →
   1区間改版2。最終mergeは毎回実行。実SQLiteで10 hitの全量storage read/decodeが最大1回、
   hitによるSQLite data_version変更0回をassert。実モデル速度の改善量ではない。
10. **未計測性能**: 60分原文の60秒/30秒、実API P50/P95/最大、TTFT/推論/本文/保存の実端末値、
    native cold/warm/各方式の同条件比較、実TCP/TLS。fixtureの仮想秒数を実測latencyに置換しない。
11. **品質評価**: J-MeetEval固定197件/16分類、gold25件、公式ruleと既存offline判定を維持。
    引用ID/quote/part/話者、truncated/malformed JSON、取消・競合等を無料で検査。
    factual recall/readability/背景・条件・否定の意味的精度、judge、全体スコアは未取得。
12. **費用**: 実API評価0件、日常APIキー未使用。cache hit時のrequest削減をmock確認。
    USD改善額は不明。共有admissionはリトライを増やさず、SoTは通常無効。
    raw runnerの価格上界予約は推定であり実課金ではない。外部hard capの設定/検証は未実施。
13. **メモリ/電池**: cacheの4MiB/32件/24時間/1件256KiB制限は維持。新tokenizer資産/依存なし。
    RAM residentは同じ上限内だが実機peak/電池/thermal改善量は未測定。低電力/熱による並列縮退を維持。
14. **通常有効**: part受理ゲート、granular cache、現行Knowledge根拠再検証、共有admission、
    有界queue/priority/aging/429/cancel/再認可。未知BYOKの並列は従来1/2を維持。
15. **gate閉鎖**: SoT通常採用、保存音声先読み候補。並列3/4は明示契約のpolicy/テスト対応のみで、
    reviewed account契約はカタログ未登録。mock合格を理由に本番既定を拡張しない。
16. **残存課題**: モデル別local tokenizerとframing照合、部分notesの意味的整合性/網羅性、native全方式
    runner/SQLite保存境界/同条件比較、人物/長期memory/資料への追加統合、実空きRAM/latencyを使う調整、
    subscriber別取消を備えたSingle-flight、より粒度の細かいSQLite書込、11既存警告、未実行UIケース。
    原文編集済み/人手編集済みenrichmentは既存レビュー扱いを保ち、自動確定memoryへ昇格させない。
17. **Git**: b93ecf42（part受理）、897d6651（cache）、d1c11298（共有admission）、
    c62447bd（Knowledge/SoT容量）、ab09712a（限定runner）、cf5a78ce（DeepSeek既定/移行）、
    5a72bfc6（生成元認可）、e808b574（重複根拠/不正評価応答）、cd1fb441（回帰fixture）、
    c6544ac6（中間notesの容量境界）。
    この文書・検証JSONを含む最後の報告commitはgit履歴を参照。
18. **ユーザー確認が不可欠な事項**: 今回の無料検証を終えるための追加操作は不要。
    将来の実API評価は独立した評価資格情報、厳密な対象データの送信許可、外部hard capが必要。
    実機の音声/STT、電池/発熱、実アカウント制限/認証と最終UIアクセシビリティは未認証。

「実装済み」「mock/host検証済み」「実モデル検証済み」「実機検証済み」「通常有効」を混同しない。
実モデル/実機での実測認証は今回追加していない。


最終source SHA256: `22154d323174e7b4327363858479ad6033e687c69a0e67fa3665833e322e8803`。
最終10群の原ログは `/Volumes/WorkspaceSSD/Development/Agents/MemoraSummaryPerformanceValidation/common-ai-quality-note-capacity/`。
最終UIの原本は `.e2e/common-ai-ui-note-capacity/report.json`（適応型/原文保存復旧/処理設定）。最終Previewは
`2026-11-15T17-32-12-ed82b16f.log`、iOS 27.2 SDKで成功、11既存警告。
これ以降の変更はdocs内の報告のみで、テスト対象コードは不変。
