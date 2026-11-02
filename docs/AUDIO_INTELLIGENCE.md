# Audio Intelligence — 統合監査・実装記録

2026-11-02。取得した `github/main` と開始時HEADはいずれも
`019622b6b8edb6d00e6f46d94d4ee6ede2d6ddcd`。以下は実コードの監査。
未提供のクラウド、端末性能、24時間連続動作を実装済みと扱わない。

## 開始時の3区分

| 区分 | 機能・コード根拠 | 境界 |
| --- | --- | --- |
| そのまま再利用 | `TranscriptionService` の SpeechAnalyzer / AnalysisContext / 確定結果と時刻 | 端末・言語・モデル資産が必要 |
| そのまま再利用 | `SourceMediaChunk`、`SourceMediaAudioExport`、`SourceMediaTranscript` | 資料の15分分割、原本時刻への加算、本文16MB制限 |
| そのまま再利用 | `SourceMediaSnapshot`、`SourceMediaCheckpointStore` | 不変コピー、前後digest照合、flock、SQLiteの完了prefix、失効世代 |
| そのまま再利用 | `SourceIntake`、PDF/OCR/Office/Web/YouTubeCaption系 | 利用可能な字幕のみ。取得不能な本文を作らない |
| そのまま再利用 | `MeetingSummarizer`、`SummaryPartScheduler`、`OnDeviceSummarizer` | 60,000文字超を部分ノート→統合。日単位の永続階層ではない |
| そのまま再利用 | `MemoraModel+SourceSummary`、SourceSummaryOptions、各テンプレート | 形式・長さ・用途・資料別指定あり |
| そのまま再利用 | 検索index / SourceTextIndex / AnswerCitations / RecordAccessPolicy | 資料・時刻・ページへの出典、個人・project・privacyの境界 |
| 要改修 | `CloudTranscriptionService` | BYOKの実APIあり。ただし全文だけ取得し時刻0へ平坦化 |
| 要改修 | `MemoraModel+Processing` → `TranscriptionService` | 保存済み録音は資料と違い全ファイル認識、区間再開なし |
| 要改修 | `RealtimeTranscriptionService` | 確定文は表示専用。別マイクtap、開始遅延、pause、dropあり。録音時計との証明なしで再利用禁止 |
| 要改修 | `FluidSpeakerDiarizationService` | 実モデル・区間・embeddingあり。ただし長時間全体のメモリ/RTF未検証 |
| 要改修 | 資料6時間 / 原本50MB / 合計500MB / stage128MB | 録音機能自体の上限ではない。backup、share、cacheにも別の容量境界あり |
| 要改修 | `AudioRecorderService`、録音draft・復旧transaction | 単一AAC、録音時間上限なし。容量の周期監視・rotationなし |
| 新規 | 条件付き品質診断、VAD候補区間、前処理の評価 | Whisper/RE-USEやLocalVQEを常時適用しない |
| 新規 | 同一設定の録音checkpoint、由来・confidence保持 | 既存recordを移行せず後方互換に拡張 |
| 新規 | Memora提供STT、購入検証、原子的な予約/精算、運営上限 | `MemoraIntelligence`は接続口だけ。販売・本番利用は禁止のまま |
| 新規 | 日別要約の永続cache・複数日階層統合 | 既存横断検索と区別する |

## 処理経路と採用判断

資料: 安全な保存 → SourceProcessingQueue → 不変snapshot → 15分export →
端末内認識 → SQLite prefix → 原本再照合 → 全体の本文 → 既存要約/検索。
録音: AVAudioRecorder + 独立したlive表示 → draft/記録の同時保存 → 保存後認識。
外部送信はautomaticで追加せず、既存BYOK・privacy判定を維持する。

FluidAudio 0.17.7のローカル実ソースを確認。Silero VADは同梱APIから利用できるが
モデルが別途必要。`VadManager.process(URL)`は全音声を配列化するため長時間では使わない。
streaming APIか小さな区間に制限する。AppleのSpeechDetectorはSpeechAnalyzer内の
検出用で、汎用音声品質分類や安全な切除の保証ではない。
単純なエネルギー判定はささやき声を無音と誤るので、認識対象の切除に用いない。
不確かな区間はすべて残し、原本は変更しない。

LocalVQEは別モデルが必要なbetaのAEC/NSで、16kHzのmic/far-end入力を持つ。
既存録音の汎用雑音除去として自動適用する根拠はまだない。軽量/強め/問題区間のみを
同一正解音声で比較するまで無加工を本番経路とする。RE-USEも本番必須にしない。
Parakeet等の日本語対応・容量・iPhone実測も未確認なので認識エンジンは増やさない。

## 段階と完了条件

1. 監査・公式価格・再現可能な最悪原価計算。既存プランを書き換えず候補を別管理。
2. BYOK構造化結果と後方互換metadata、拒否/不正時刻/旧保存の検査。
3. 保存済み録音をbounded経路に接続。原本変更・取消・削除後結果を防ぐ。
4. 品質診断/保守的なVADの評価経路、空き容量監視、24時間chunk計画の検査。
5. サーバー予約/精算の非公開基盤。認証/購入/削除を含む統合検査まで提供不可。
6. 実機24時間・日本語品質/RTF・日別要約/検索の追加。測定なしの高速化率は出さない。

## 実機・品質評価の受け入れ条件

RTF = monotonic処理秒 / 原本秒。10分・1時間・6時間・24時間の同じ音声を使用。
VAD、品質判定、軽/強NS、端末認識、cloud、話者、要約、全体を別々に測定する。
端末名/OS/モデルrevision/発話比率/冷温/電池/thermal/peak RSS/原本hashを記録する。
日本語会話・雑音・小声・複数人・長無音・音楽・固有名詞・重なりの人手正解に対し、
CER（文字正規化規則も固定）、WER、時刻誤差、話者DER、短相づちの欠落を比較。
VAD前後の精度劣化を確認し、不明なら切除を有効にしない。
simulator/合成波/host検査は日本語認識精度・iPhone RTF・電池の証明ではない。

録音のバックグラウンドaudioは既存設定を使う。強制終了後の録音自動再開はしない。
OS停止・電話・入力変更・熱・容量不足を含む実機試験まで24時間連続動作を保証しない。
rotationはpause/stop/startを繋ぐだけでは欠落を防げない。共通音声時計とdurableな
manifest、再生・backup・復旧への統合が揃うまでは単一録音の保存設計を保持する。

## 今回のアプリ実装と検査

- BYOK: OpenAI Whisperのverbose_json区間、Deepgram Nova-3のutterancesを
  読み、開始/終了時刻・匿名クラスタ・取得できたconfidence・engine/model/言語を
  `TranscriptSegment`へ保存。confidenceをspeaker確信度へ転用しない。
  有料のcloud話者分離は自動要求しない。speakerが返った場合に保持するdecoderを持つ。
  時刻なし本文を時刻0へ平坦化しない。旧recordはoptionalな追加属性なしで読める。
- BYOK送信直前にもworkspace/record/privacy/設定を再検査。自動・取り込みに
  クラウド許可を付けない。Memora提供STTへの接続は追加していない。
- 保存済み録音: `RecordedAudioTranscription`が既存queue/export/snapshot/SQLiteを
  再利用。原本は2GBまでの64KB逐次コピー。15分ずつ認識し、原本の開始/終了時刻を
  復元。失敗prefixは完成扱いにせず、同一hash/OS/locale/用語/pipelineで再開する。
  source側の旧key形式・50MB制限・snapshot保護は維持。live文の再利用は未有効。
- `SourceMediaChunk`の計画は24時間/96区間まで。音声専用importは従来から50MB制限が
  なく、この録音経路で処理可能。資料/会話/Share Extensionの50MBを全体解除して
  backupや受領transactionを壊すことは避けた。2GBを超えるPCM等は別対応が必要。
- 録音開始前・15秒ごとに256MBの空きを確認。低容量時は既存の停止/保存/復旧経路へ
  渡す。保存済みデータを自動削除しない。iOS停止時にtimerが必ず動く保証はない。
- 評価用: `AudioSignalInspector`は4096frameずつ全channelを読み、形式・音量・peak・
  clipping・低energy比率を測る。雑音/音楽の判定と称さない。
  `FluidVoiceActivityEvaluator`は明示的に渡されたlocalモデルでstreaming推論。
  自動download/送信なし。候補は低い確率・短い発話も残し、前後750ms、2秒以内を
  merge。`VoiceActivityTimeline`が候補の連結時刻を原本へ戻す。
  **この評価器・切除・ノイズ除去は本番認識経路で有効にしていない。** モデルと
  日本語正解コーパスの実測がないので、効果・節約を実績に計上しない。
- FluidAudioの追加確認: pinned 0.17.7の`OfflineDiarizerManager.process(URL)`は
  `AudioSourceFactory.makeDiskBackedSource`を使う。全PCMの配列化ではなかった。
  長時間のembedding/clustering負荷と一時領域はなお実機未測定。

検査（2026-11-02、macOS host）:

| 検査 | 結果・範囲 |
| --- | --- |
| run-cloud-transcript-checks.sh | PASS。公式形式fixture、時刻/終了、匿名話者、confidence、重複発話保持、旧/new Codable、不正時刻拒否 |
| run-source-extraction-cache-checks.sh | PASS。既存hash/SQLite/失効/変更/locale検査。実50MB超WAV→2個のAAC export、後半失敗で部分非公開、store再生成後のsuffix再開、全完了再利用、低容量拒否を追加 |
| run-source-media-export-checks.sh | PASS。実AVFoundation範囲export、96区間計画、flock/孤立stage/容量/取消検査 |
| run-audio-intelligence-checks.sh | PASS。実stereo波形の逆位相/音量/clipping、低確率・短発話保持、不明判定fallback、原本時刻mapping。学習モデル推論はfixture外 |
| bitrig preview -platform iOS | 音声基盤追加後成功。iOS 27.2 SDK、既存警告11件。追加の最終buildは別途記録 |

端末内RTF/CER/WER/DER、学習VAD、実BYOK、日本語認識境界、小声、24時間実録音、
電池/thermal、容量低下の実機通知、UI操作は未検証。音声/個人情報をlogへ追加していない。

## 長時間要約の追加統合

`SummaryNoteHierarchy`を既存の部分ノート→全体統合の間に追加した。
ノート合計が60,000文字を超える時だけ、時間順のbounded groupを段階的に整理する。
短い入力は追加APIなし。各groupの上限、最大512部分・8段階、縮まらない出力・
空出力・取消で停止し、無限再試行しない。日時/話者/数値/否定条件/segmentID/逐語引用の
保持を中間promptへ指定し、最終の既存出典検証・テンプレート・権限callbackを維持。
この1記録の統合は、日別cache/複数日階層の実装ではない。

- `run-summary-hierarchy-checks.sh`: PASS。順序と全入力のgroup分配、短い入力の追加呼出なし、
  非縮小/過大出力/取消の停止。reducerはfixtureなので実AIの情報保持率は未検証。
- `run-summary-reliability-checks.sh`: PASS。既存の長いstream/遅い初token/EOF/DeepSeek reasoningの
  有界処理を再確認。virtual clockとSSE fixtureで、実providerの通信ではない。
- `run-source-summary-checks.sh`: PASS。既存の形式/長さ/厳格cloud許可、13の停止中race、
  SQLite失敗時保持を確認。古いfixtureに欠けていた`persistBatch`を実SQLiteへ合わせた。

費用・販売条件と全人数シナリオは [運用設計](AUDIO_CLOUD_OPERATIONS.md) と
[生成表](AUDIO_COST_SCENARIOS.md)。サーバー台帳コアの11件の実SQLite検査はPASSだが、
認証・App Store購入検証・D1/provider/R2のE2Eが完了するまで有料cloudを提供しない。
