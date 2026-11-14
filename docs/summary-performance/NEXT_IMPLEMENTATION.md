# 継続作業の設計メモ

直近の基盤commit: c425146f（通信再利用）。Phase 1 / lossless入力 / 共有能力・容量計画・制限付き並列の単位までcommit・push済み。実モデル評価は利用者指定で実行しない。未実装を完成扱いにしない。

## 次の単位: cache / 統合

既存資産を再調査:

- ModelCapabilities / ModelCapabilityOverrides / TokenBudgetManager / TokenEstimateは共通正本。新しいモデル表を作らない。
- AgentGenerationPolicyは既にOpenAIのusage opt-in・モデル固有tool条件を扱う。要約へ丸ごと適用すると推論を無断変更するので、usage取得など責務だけを共有する候補。
- SourceExtractionCache + SourceExtractionPersistenceは既存の抽出cache。SourceMediaCheckpointStore / PDFCheckpointStoreは既存の確定部分再利用。NativeAIResponseCacheは表示cacheで用途が異なる。
- SourceExtractionPersistenceは既存cache SQLite（32MiB、12件、7日、payload hash/secure_delete、backup除外）。LocalStoreは既存のrecords SQLiteの汎用documents。追加DBは不要。どちらを利用するかはlifecycleの安全性から決める。
- PendingSummaryJobは送信前attemptStartedAtを保存し、再起動で勝手に課金を再実行しない。requiresUserRetryを維持。途中結果は完了要約に保存しない。

cache採用時の条件:

1. 元のレコード/ソース、scope、account/credential revision、provider/model/endpoint、原文/話者、glossary、sourceContext、分析prompt/spec版をキーに含める。モデル名の表示名変更は意味が無ければ分離。APIキーそのものを保存・出力しない。
2. partNotesは既存LLM呼出しの結果を再利用し、新たな分類・理解呼出しを足さない。長さ/順序はpartNotesの意味に影響しないが、抽出focusが異なるtemplateは原文から追加分析が必要。旧knowledgeだけを「全原文を理解済み」とみなさない。
3. 完了したtransport・有界な構造・根拠ID/引用を確認した部分だけ再利用。不明な実行結果は自動再送しない。部分memoをAI事実の確定や人物記憶への許可に昇格しない。
4. cache読取/再利用前・次の送信前・保存前に既存authorizeを再確認する。scope必須、authorize無しではcacheを使わない。
5. 失効leaseを持ち、削除/権限変更/restore/workspace/account変更後に古いworkerがcacheを再作成できないようにする。物理削除を保存処理と矛盾させない。可逆なcache破棄はユーザーデータの削除ではない。
6. TTL / LRU / entry・総容量を制限。破損cacheで既存記録のdecodeを壊さない。UserDefaultsへ本文を置かない。backup/exportへcacheを混入しない。

主なlifecycle調査箇所:

- MemoraModel.meetings / projectSources didSet、aiWorkspaceGeneration / currentTeamID
- MemoraModel+Meetings updateMeeting / commitMeetingChange（原文・話者・privacy編集）
- MemoraModel+RecordPrivacy setRecordPrivacy
- MemoraModel+Trash、Backup restore、Workspace、account/logout
- MemoraModel+SourceExtractionCleanup discardSourceExtraction（既存source cacheの破棄）
- MemoraModel+SummaryGeneration / SourceSummary（生成・authorize・確定保存）

## 残り

- SoT Route B: 全体の事実/撤回/条件を共有した計画とセクション並列、同じSummaryKnowledgeと既存parser/validatorに統合。実品質/費用の採用ゲートが無い候補は既定にしない。別の要約エンジンを新設しない。
- 通信はjob単位URLSession再利用とSSE off-mainまで実装済み。TRANSPORT_DESIGN.md参照。実TCP/TLS・実機応答は未検証。
- 確定STT区間: 既存SourceMedia/PDF checkpointとSpeechAnalyzer/recording finalizedフラグを調べる。暫定STTや未確定話者にクラウド先行処理を追加しない。
- 評価: 保存済み本番相当応答への公式rule runnerはある。Judge/生成APIは未実行。課金ランナーを実装する場合も独立資格情報とrequest/費用上限が必須。
- 全10群の無料回帰、適応型要約/復旧E2E、最終preview、docsと未検証一覧、意味単位commit/push。

外部作業ディレクトリ: /Volumes/WorkspaceSSD/Development/Agents/MemoraSummaryPerformanceValidation。
最新成功iOS preview: 2026-11-14T22-24-37-56c97a02.log（11既存警告）。phase3-shared-pipeline.log / phase3-selected-model-r2.log / phase3-shared-model-regression.log / phase3-shared-capabilities.logに無料検証。
