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
