# Memora Audio Intelligence — 今回の統合報告

2026-11-02。全6 Phaseの完了宣言ではない。実装した安全な基盤と、本番提供に残る条件を分ける。
開始時にGitHub mainを取得し、`019622b6`と一致することを確認。mainのまま作業。
調査だけで止めず、iOSアプリ・検査・課金台帳コアを実装した。push/課金/契約/配備は行っていない。

追補: 初期オフの数値計測・端末内JSON共有・ローカルCER/WER/RTF集計を追加した。
録音/live/保存音声/資料抽出/BYOK/話者/要約を計測し、部分区間と再開を性能比較から区別する。
live認識も既存の文字起こし言語設定を使う。原本・本文・record ID・path・資格情報をログに含めない。
測定方法・追加ファイル・実測前の制限は[計測手順](AUDIO_MEASUREMENT.md)。
保存音声/音声動画資料では高温時に新しい変換/認識の開始を保留し、保存済みprefixから
明示的に再試行できる。録音/liveはこの条件で止めない。実機の冷却/電池効果は未測定。
録音終了時も復旧と同じ確認基準を使い、未確認音声を推定長で自動転写しないようにした。
終了/保存/再試行のguardと数値計測・実SQLiteの検査は[録音確定の追補](RECORDING_FINALIZATION.md)。
長時間再生のUInt32一括変換を最大2区間の予約へ変更し、古いcallbackと取消済みtickerを
失効させた。[再生の検査と残件](AUDIO_PLAYBACK.md)。録音rotationはまだ有効にしていない。

## 1. 変更した機能

- 保存済み録音も、原本の不変コピー・15分export・端末内認識・SQLite再開の経路へ接続。
  最大24hを96区間で計画、録音側原本2GBまで。完了前のprefixを完成扱いにしない。
- BYOKのOpenAI/Deepgram結果を区間の開始/終了・匿名話者・取得できたconfidence・
  engine/model/言語として保存。時刻なし本文を0秒にしない。旧データは読める。
  送信直前の許可再検査とDeepgram MIP opt-outを追加。
- 録音前・15秒ごとの空き容量確認。256MB未満で既存の保存・復旧経路へ停止を通知。
- 全channelの逐次品質測定、FluidAudio Silero streaming評価adapter、保守的候補と原本時刻mapping。
  評価器と切除/NSは本番自動処理に未投入。
- 長い部分要約ノートをboundedな階層で統合。短い記録は追加APIなし、非縮小/過大/取消で停止。
- serverの非公開予約・精算台帳コアと、全4,480組合せの費用計算を追加。

## 2. 再利用した既存実装

SpeechAnalyzer・用語集、SourceProcessingQueue、SourceMediaSnapshot/StageLease/AudioExport、
SourceMediaCheckpointStore/SourceExtractionPersistence、record保存/復旧transaction、
RecordAccessPolicy、CloudAIService streaming、MeetingSummarizer/テンプレート/引用検証、
既存の検索・Ask AI・資料取り込み。FluidAudio 0.17.7を再利用し、新規依存ライブラリなし。
Library/Journal/Ask AI/Marketplace、composer・作成メニュー・Glass・PPTX/DOCX・連携のUI変更なし。

## 3. 追加・変更ファイル

アプリ追加:
`AudioSignalInspector.swift`、`AudioSignalReport.swift`、`CloudTranscriptDecoder.swift`、
`FluidVoiceActivityEvaluator.swift`、`RecordedAudioTranscription.swift`、`VoiceActivityTimeline.swift`、
`SummaryNoteHierarchy.swift`（すべて`App/`）。

アプリ変更:
`AudioRecorderService`、`CloudTranscriptionService`、`MemoraModel+Processing`、`ProcessingService`、
`SourceMediaCheckpoint`、`SourceMediaCheckpointStore`、`SourceMediaChunk`、`SourceMediaExtraction`、
`SourceMediaFailure`、`SourceMediaSnapshot`、`SourceMediaStaging`、`TranscriptSegment`、
`TranscriptionService`、`MeetingSummarizer`、`SummaryPrompt`（`App/*.swift`）。

検査:
`tools/checks/AudioIntelligenceChecks.swift`、`CloudTranscriptChecks.swift`、
`RecordedAudioTranscriptionChecks.swift`、`SummaryHierarchyChecks.swift` と各runner、
既存`SourceMediaExportChecks`/`SourceExtractionCacheChecks`/cache runner/`SourceSummaryModelFixture`。

server:
`backend/audio-intelligence/ledger.sql`、`ledger.mjs`、`test_ledger.py`、`README.md`。
費用計算: `tools/checks/audio-cost-scenarios.py`。
文書: この報告、`AUDIO_INTELLIGENCE.md`、`AUDIO_CLOUD_OPERATIONS.md`、`AUDIO_COST_SCENARIOS.md`、
`PRICING.md`、`IMPROVEMENT_BACKLOG.md`、`OPENCODE_IMPLEMENTATION.md`。
`Project.json`/entitlements/既存SQLite record schemaを変更していない。

## 4. 検査と結果

| 検査 | 結果と範囲 |
| --- | --- |
| cloud transcript | PASS。provider fixture、時刻/匿名話者/confidence、旧保存、異常値拒否 |
| source extraction cache + recorded audio | PASS。実50MB超WAV・2 AAC範囲export、失敗prefix非公開、SQLite再生成でsuffixのみ再開、全完了再利用、低容量拒否、既存hash/世代/locale/原本変更 |
| source media export | PASS。AVFoundation、96区間計画、flock・容量・取消・stage回収 |
| audio intelligence | PASS。実stereo PCM、低energy/clipping、短発話/低確率保持、VAD不明時fallback、時刻mapping |
| summary hierarchy | PASS。fixtureによる順序・全入力group分配・上限・非縮小/取消停止 |
| summary reliability | PASS。長いSSE・遅い初token・EOF・reasoning除外（仮想clock/stream） |
| source summary | PASS。保存/許可/形式/13race。古いfixtureのAPI不足を修正して実行 |
| ledger | 11件PASS。実SQLite、二接続の同時予約・全体上限rollback・精算・不明usage・期限失効・全体並列枠・価格/台帳改変拒否 |
| adapter | `node --check` PASS。D1 bindingの実接続検査ではない |
| pricing | 1,280 audio / 3,200 planケースPASS。全枠・税/手数料/FX/年額/人数/値上げ/retry。赤字も保持 |
| diff | `git diff --check` PASS |

最終`bitrig preview -platform iOS`: **成功**、iOS 27.2 SDK、既存警告11件、preview更新済み。
build log: `logs/2026-11-02T18-36-44-ac663951.log`（Bitrigのbuild領域）。
全suiteの反復や外部有料API呼び出しは行っていない。

## 5–6. 未検証・端末内RTF/精度

iPhone実測のRTF、CER/WER/DER、battery/thermal、24時間連続録音、中断/容量低下の実通知、
SpeechAnalyzerの日本語境界・小声・重なり、実Silero/LocalVQE、実BYOK、D1/認証/購入/R2は未検証。
リポジトリに評価用の実日本語音声/正解コーパスは見つからなかった。合成波/fixtureを認識精度に換算しない。
RTF=処理秒÷原音声秒。10分/1h/6h/24hの端末別測定手順は`AUDIO_INTELLIGENCE.md`。

## 7–9. 最新STT価格・月720h・VAD

モデル別公式ページ確認値: CF Whisper $0.02718/h、CF Turbo $0.03078/h、Groq Turbo $0.04/h、
Groq large v3 $0.111/h、OpenAI Whisper $0.36/h、OpenAI miniは推定$0.18/h、
Deepgram multilingualは現料金表の保守値$0.552/h、用語強調込み$0.63/h。
話者分離は追加$0.002/分なので自動要求を外した。公式ページ間の差/旧indexを明記。
OpenAI Whisperは公式モデルページのDeprecated表示も確認。既存BYOK互換を維持し、
時刻対応・価格が異なる新モデルへ自動切替は行わない。
リンクと課金単位は [運用設計](AUDIO_CLOUD_OPERATIONS.md#stt比較)。日本語精度による採用は未決定。

720h全量STT（FX200）はCF Turbo4,432.32円/Groq Turbo5,760円/OpenAI Whisper51,840円。
1hごとのLLM要約の仮定原価はさらに約1,598.40円。Ask AI/保存/転送/運営費は別。
**端末内録音だけならMemora負担のSTT/API原価は0**で、端末保存・電池負担は残る。
VAD後25%を実送信した仮定のCF Turboは1,108.08円。75%削減は実績ではなく、
server VADが元の送信長課金まで減らすと仮定しない。時間短縮・品質向上は未測定。

## 10–11. 推奨cloud構成・プラン

現時点は端末内/BYOK継続を推奨。将来案はWorkers + Queues + D1 + R2 Standard +
品質評価後の安価なSTT。基本固定費$5/月（FX160/200:800/1,000円）、従量分は別。
個人CloudKit、サービス側保存、team認証/権限/費用を分離。原本の永続cloud保存は標準にしない。

既存プランを維持。cloud付き別候補として2,480円/20h/300credit、7,980円/100h/700creditを比較。
FX200・手数料30%・税10%・値上げ1.5倍・retry1.25倍・余裕10%・100人で全枠使用の場合:

| 候補 | 最大変動原価 | 純収入 | 固定費配賦後利益 | 利益率 |
| --- | ---: | ---: | ---: | ---: |
| Cloud Plus 2,480円 | 973.50円 | 1,578.18円 | 594.68円 | 37.7% |
| Cloud Max 7,980円 | 3,124.69円 | 5,078.18円 | 1,943.49円 | 38.3% |

1人運用のCloud Plusは月395.32円赤字。Cloud Maxは953.49円残る仮定だが、費用未確定条件を含む。
同価格でcloudを付けるunlimited/teamの別候補は100人でも利益率8.7%/2.3%で推奨しない。
全1/10/100/1,000/10,000人・年額10/11/12か月価格は[生成表](AUDIO_COST_SCENARIOS.md)。
年額は当初12か月価格の候補。予算内の実サービス/全費用が証明されるまで販売しない。

## 12. 次に残る作業

1. 同意済み日本語コーパスと実iPhoneで精度/RTF/電池を測り、VAD切除/NS採否を決定。
2. live時計と録音の対応、rotation manifest・再生・backup・復旧、全資料経路の大容量対応。
3. 認証/購入/同意失効、provider実usage、価格監視・異常利用、R2削除、D1 staging E2E。
4. 日別永続要約と複数日階層cache。現在の横断Ask AIと引用/検索の回帰を実データで確認。
5. 実費と人数から枠/価格/年額を確定し、監視・復旧・利用制限を検証してから公開判断。
