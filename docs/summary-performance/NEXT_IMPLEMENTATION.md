# 継続作業の設計メモ

現在の残タスクは[現況一覧](STATUS.md)と[共通AI改善](../common-ai/IMPLEMENTATION.md)。今回、録音中の先行AI分析は対象外であり、下記の過去計画を実装予定として扱わない。以下は各実装単位時点の履歴であり、古い「未実装」「最新」は当時の状態を指す。

## 送信制御・検証guard後の音声単位

保存済み/manifest seal済み音声の1区間先読み変換を候補実装。[設計・失敗を含む検証記録](AUDIO_PREPARATION_PIPELINE.md)。不変snapshot、確定prefix checkpoint、認識の逐次順序、原本変更時の拒否を維持する。hostで実WAV/AAC変換と認識fixtureの重なり・逐次同等・キャンセル・熱再検証・suffix-only再開を確認。通常の`.validated`は逐次のまま。録音中の先行推論、実機の速度/電池/発熱、実モデル評価は未実装/未検証。Phase 5全体は未完了。

初回統合時点: [2026-11-15統合検証](VALIDATION_2026_11_15.md)。以後の追加単位は[現況一覧](STATUS.md)を参照。

基盤commit: 6ef48197（SQLite part cache）、da1167e1（階層並列とprefix）。数値集計/JSON off-main/オフライン比較レポートも追加。実モデル評価は利用者指定で実行しない。未実装を完成扱いにしない。

## 次の単位: 階層並列 / SoT候補 / 統合

既存資産を再調査:

- ModelCapabilities / ModelCapabilityOverrides / TokenBudgetManager / TokenEstimateは共通正本。新しいモデル表を作らない。
- AgentGenerationPolicyはusage処理だけを要約と共有済み。推論/出力policy全体を要約へ流用しない。
- SourceExtractionCache + SourceExtractionPersistenceは既存の抽出cache。SourceMediaCheckpointStore / PDFCheckpointStoreは既存の確定部分再利用。NativeAIResponseCacheは表示cacheで用途が異なる。
- SourceExtractionPersistenceは既存cache SQLite（32MiB、12件、7日、payload hash/secure_delete、backup除外）。LocalStoreは既存のrecords SQLiteの汎用documents。追加DBは不要。どちらを利用するかはlifecycleの安全性から決める。
- PendingSummaryJobは送信前attemptStartedAtを保存し、再起動で勝手に課金を再実行しない。requiresUserRetryを維持。途中結果は完了要約に保存しない。

長文part cacheを既存LocalStoreへ実装済み（SUMMARY_ARCHITECTURE.md参照）。以後の拡張でも維持する条件:

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

- SoT Route B: 候補実装済み。全原文/共通計画/同じ抽出JSONを共有し、既存parserへ統合。mockの順序/根拠/不正計画/429を通過。SummaryOptimizationGate.reviewsは空で通常無効。実品質/費用/速度なしにgateを開けない。
- 通信はjob単位URLSession再利用とSSE off-mainまで実装済み。TRANSPORT_DESIGN.md参照。実TCP/TLS・実機応答は未検証。
- 確定STT区間: 既存SourceMedia/PDF checkpointとSpeechAnalyzer/recording finalizedフラグを調べる。暫定STTや未確定話者にクラウド先行処理を追加しない。
- 評価: 保存済み本番相当応答への公式rule runnerはある。Judge/生成APIは未実行。課金ランナーを実装する場合も独立資格情報とrequest/費用上限が必須。
- 全10群の無料回帰、適応型要約/復旧E2E、最終preview、docsと未検証一覧、意味単位commit/push。

外部作業ディレクトリ: /Volumes/WorkspaceSSD/Development/Agents/MemoraSummaryPerformanceValidation。
最新成功iOS previewはphase4-cache-preview-commit.jsonに記録（11既存警告）。phase3-shared-pipeline.log / phase3-selected-model-r2.log / phase3-shared-model-regression.log / phase3-shared-capabilities.logに無料検証。

2026-11-15 cache単位: phase4-cache-prompt-reviewed.log / phase4-cache-lease-reviewed.log / phase4-cache-source-final.log / phase4-cache-background-final.logでhost検証。全10群とE2Eはまだ今単位で再実行していない。cache primitive/lifecycleは実SQLite、model stateとAPI応答はfixture。

## 2026-11-15 最終レビュー修正

キャッシュのhitごとの全量SQLite書き戻しを廃止し、LRU touchをRAMに保持して次回write時に反映する。再起動を挟むLRUは最後の永続化時点となる。10 hit/変更なしowner cleanupでSQLite data_versionが不変であることを実ストアのhost testで確認。起動cleanupもleaseを検証し、古いcleanupが新世代を消去しない。空のcacheではrecord配列の追加比較を避け、分析開始時点で保守的な存在flagを立てて未完了workerの失効を維持する。

fence付き不完全notes JSONを完了した部分結果として扱わない。生成factのspeakerIDsは引用した原文segmentのspeakerIDだけを受理し、不一致はuncertainへ下げる。過去本文・編集は変更しない。SummaryPlanning/SummaryReadingの追加回帰とiOS preview成功（既存11警告）。続く最終10群も成功（統合検証参照）。

## 統合確認後に残る作業

通常利用の並列文章生成gateは閉鎖を維持。Phase 5の音声先行処理、実費上限を保証する生成/Judge runner、全job横断rate制御は未実装。実APIの品質/速度/費用と実機の電池/発熱等は未検証。PNG復旧UIの入口は既存フラグで無効のため未検証。最終10群はquality-2026-11-15-final、UIはsummary-performance-narrow-focused / summary-performance-supported-confirmedに記録。次回は完了済みの無料確認を繰り返す前に統合検証の残存課題を確認する。

## a715fdd2後の追加単位

[要約ジョブ共通の送信制御](SUMMARY_REQUEST_SCHEDULING.md)を実装。上の全job横断rate制御の残課題のうち、要約の同一endpoint/認証scopeの並列数共有、429/Retry-After、FIFO/待機上限/キャンセル/送信前再認可を対応する。未知のRPM/TPMは依然不明、token bucketや全Ask AI処理への統一は未実装。音声パイプラインと実モデル評価の状態は変わらない。

## 送信制御単位の検証後

送信制御は7f224b18。無料10群は9群成功＋next-generation再実行成功、途中の音声fixture失敗は未確定のままログを保持。UI2件/preview成功、詳細はSUMMARY_REQUEST_SCHEDULING.md。続けて、共有treeの変更で成功結果が混在しないようrun-quality-checksに内容/ファイルrevision指紋のguardを追加。9単体テストと実2群のsmoke成功。全10群を新guardで再実行した結果ではない。実モデル/実機、RPM/TPM、音声先行処理、費用上限付きrunnerは引き続き未実施/未実装。

音声候補単位の最終確認: ガード付き全10群が同一source fingerprintで成功、agent-free E2E 2/2、iOS preview成功（既存11警告）。詳細と原本変更テスト作成中の失敗はAUDIO_PREPARATION_PIPELINE.mdとaudio-preparation-results-2026-11-15.json。通常先読みgateは閉鎖。

## 確定区間の版管理単位

[区間版/配列範囲/保存済み版との照合](SETTLED_CHUNK_REVISIONS.md)を既存STT checkpointへ追加。旧形式・任意情報の破損・容量上限で本文を失わない。ガード付き全10群・E2E2件・preview成功。録音中のsealed part identity、版更新イベント、先行分析consumer、横断利用は未接続。実モデル/実機は未検証。[現況一覧](STATUS.md)を正本とする。
