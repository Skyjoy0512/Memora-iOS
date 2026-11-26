# Audio Intelligence — 計測手順と検証境界

2026-11-02。数値を採取する実装であり、実機のRTF・精度・24時間稼働の測定結果ではない。

## 端末での使い方

設定 › 診断とプレビュー › 音声処理の計測を開き、「音声処理を計測」をオンにする。
初期値はオフ。次に開始した録音・保存音声の文字起こし・音声/動画資料の抽出・
BYOK文字起こし・話者解析・要約を計測する。既存の同意・APIキー・用語集・
資料アクセス権限を変更せず、計測目的のクラウド送信やモデルのダウンロードはしない。

録音の確定は`recordingFinalization`として別traceに記録する。音声metadataの確認を
`verification`、SQLite保存を`persistence`に分け、確認不能な長さは分母に採用しない。
録音中の編集metadataの周期保存に失敗した回数は`draftCheckpointFailure`に記録する。
[終了/復旧/再試行の判定](RECORDING_FINALIZATION.md)。

「音声品質も測定」は次の処理から適用する。保存音声と音声/動画資料の15分以下の
変換済みチャンクを4,096フレームずつ読み、サンプルレート・チャンネル・codec・
RMS dBFS・peak・clip比率・低energyフレーム比率を記録する。原本は変更しない。
低energy比率を発話なし/VAD/雑音率とみなさず、これを根拠に音声を削らない。
追加の読み取りコストがあるため、速度を比較する測定では同じ設定を使う。

処理後に「更新」し、結果・処理時間・原音声時間・RTF・再利用区間数・採取メモリを確認する。
「計測JSONを共有」で数値JSONを明示的に書き出せる。「計測ログを消去」は診断cacheだけを
消去し、録音・本文・要約・SQLiteの再開checkpointには触れない。
スイッチをオフにすると実行中の旧計測も書き込みを失効する。オンに戻しても旧計測は復活しない。

## 記録するもの

- 待機、snapshot、export、モデル準備、認識、upload、decode、品質、VAD、話者分離、
  要約、原本再検証の実行時間。実行した工程だけを記録する。
- success/empty/failed/cancelled/unavailable/interruptedなどの型付き結果と、完了/再利用区間数。
- 録音のpause/resume、audio interruption、入力機器切断、audio reset、容量停止、
  live入力buffer dropの数。発話テキスト・音声・ファイル名・path・元record ID・
  URL・APIキー・モデル応答・生のエラーメッセージは記録しない。
- `uname`の機種識別子、OS数値版、アプリversion/build、simulatorフラグ、品質測定設定。
  端末の名前・所有者・恒久的識別子は取得しない。trace IDは処理ごとの独立した乱数。
- 録音は約15秒ごと、その他の処理は約5秒ごとのアプリ`phys_footprint`、端末電池残量/充電、
  低電力モード、thermal state（0 nominal / 1 fair / 2 serious / 3 critical）。
  battery monitoringは計測中だけ参照計数で有効にし、最後の計測後に元の設定へ戻す。

各traceはevents/samples各256件・品質結果128件まで。最初と直近のsamplesを残し、
省略数と全期間のstage集計・採取最大メモリ・最初/最後の電池・最大thermal stateを保持する。
cacheは直近12処理、2MiB以下、端末Caches内のprivate directory/fileにatomic保存する。
7日以上更新のないcacheは次回読み込み対象外。OSによるCaches回収では失われ得る。
再起動で読み込んだrunningはinterruptedへ変更し、録音やクラウド送信を再開しない。
古い世代・順序が逆転した更新は拒否する。保存失敗は本来の処理結果を変更しない。

OSLogにも同じ型付き数値の要点を出力する。subsystem `app.memora.audio`、
category `AudioMetrics`。既存の内容を含まないsignpost（category `Processing`）も維持する。
OSLogの保存期間はOS側の管理。アプリ内「消去」はOSLogの消去を保証しない。

## RTFとリソース値の読み方

`RTF = 処理秒 / 元音声秒`。完了した60分を6分で認識した場合は0.1。

- 全体RTFはsuccess/emptyでのみ表示し、待機・コピー・変換・計測自体のコストを含む。
  再開では元音声の全長が分母になるため、新規処理の性能値と比較しない。
- stageのRTFは今回success/emptyまで完了した区間の時間/音声長で算出する。
  失敗・中断中の区間の予定長を、認識済み音声長とみなさない。
  `wallSeconds/audioSeconds`は試行全体の時間/予定長であり、stageの完了RTFとは別。
- live文字起こしは録音時計との対応が未確立のため、音声時間とRTFを捏造せず省略する。
  録音自体もRTFは表示しない。録音・転写・要約は別traceであり、記録開始から全工程終了までの
  単一の実測値として自動結合はしない。
- メモリは採取時のアプリ全体のfootprintであり、瞬間最大値や機能単独の消費量ではない。
  電池/thermal/低電力状態は端末全体の値。充電・他アプリ・通信・画面の影響を含む。
  simulatorの電池は取得不能なら欠測になる。OS suspend中のsamplesや実消費電力は取得できない。
- 計測をオンにしたまま同じ条件で比較する。最初のモデル準備/ダウンロード、cache再利用、
  充電状態、温度、バックグラウンド遷移、ネットワーク待機を区別する。

## ローカル集計・精度比較

共有したJSONをMac上の任意の検証用フォルダに置く。以下は外部APIを呼ばない。

```bash
python3 -B tools/checks/audio-measurements.py report metrics.json > numeric-report.json
python3 -B tools/checks/audio-measurements.py quality reference.txt hypothesis.txt \
  --audio-seconds 600 --elapsed-seconds 60 > quality-report.json
```

`report`は環境/build/品質測定設定、engine、stage、新規/再開ごとにmedian・p95 RTFを分ける。
未完了traceをthroughput集計へ含めない。JSONは最大2MiB/12処理。出力に元のtrace IDや
入力の内容を転載しない。不正入力時もpathや入力テキストをエラーへ表示しない。

`quality`の入力はローカルの正解文と認識文（各256KiB以下）。NFCで正規化し、CERは空白のみを
除外する。否定、数字、句読点、大小文字、全角/半角を勝手に同一視しない。
WERは空白区切りなので、分かち書きのない日本語はCERを主指標にする。
空の正解文のCER/WERは未定義（null）。編集距離はrolling rowで計算し、
2,500万比較セルを超える別内容は、時刻を合わせた短い抜粋への分割を求める。
音声秒と処理秒は両方を明示したときだけRTFを算出する。
文字起こし本文はこのCLIから書き出さず、通常の出力には件数・編集距離・比率だけを含める。

## 実機検証マトリクス（残件）

保存音声と音声/動画資料の端末内認識は、各未完了チャンクの変換前・変換後・認識直前に
OSのthermal stateを確認する。nominal/fairでは続け、serious/criticalでは新しい認識を始めず、
数値ログをdeferredとして既存の再試行経路へ返す。完成前の本文は公開せず、原本と保存済みprefixは
維持する。温度が下がってから明示的に再試行すると保存済みprefixの次の未完了区間から続ける。
全チャンク完成済みのcache再利用にはこの停止条件を加えない。録音/liveを自動停止せず、
実行中の認識を強制停止したり、冷却後に自動再開/外部送信したりはしない。
低電力モードでの遅延や本体の温度/電池改善効果は未実装/未測定。

同意済み正解音声を使い、同じ機種/OS/buildと条件で各3回以上実行する。
10分・1時間・3時間・8時間・24時間相当の連続チャンクを分け、通常日本語、雑音、小声、複数人、
長い無音、音楽/環境音、専門用語/固有名詞、重なり発話を含める。
CERに加え、時刻のずれ、話者一致/DER、原本へのジャンプ、音切れ/再開を確認する。
録音はAVAudioRecorderの実収録で、処理は既存原本でも分けて測る。

端末内のApple Speech認識は原本の全区間を使う。許可されたBYOKクラウド文字起こしの
単一ファイルでは、ローカルの音声区間検出で短縮した一時ファイルを条件付きで送信する。
短縮できない場合は原本を使い、短縮できた場合は発言開始と終了を原本時刻へ戻す。
VADの有無は同じモデル・用語集・音声による対比較で評価する。短い相づち、ささやき、
語尾、重なり、音楽混在の欠落を人手正解で確認し、話者区間と原本時刻の対応を照合する。
ノイズ抑制の比較は候補方式の検証タスクとして扱う。実BYOKでの比較には送信同意と予算枠が必要。

24時間録音のローテーション/manifest/再生/backupの統合、live確定区間の再利用、
実サービスのusageと請求額、VADの実送信秒・実料金・転写品質の比較も未検証。
ログを採れることは24時間稼働保証や認識品質の証明にはならない。

## 長時間保存音声のホスト計測（2026-11-25）

```bash
bash tools/checks/run-source-extraction-cache-checks.sh --recorded-audio-hours 1 3 8 24
```

15分の16 kHzモノラル合成AACを区間ごとに複製し、別プロセスと新規チェックポイントで各条件を処理する。
実装の原本スナップショット、AVFoundationでの結合・区間書き出し、SQLiteへのチェックポイント保存、
時刻補正、一時ファイルの削除を通す。認識器は各チャンクに固定の開始・終了時刻を返す。
Apple M4 Max、macOS 27.2で各条件を1回測定した。

| 原本 | 完了チャンク | 原本バイト数 | 処理秒 | 書き出し秒 | プロセスCPU秒 | プロセス最大RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1時間 | 4 | 7,563,144 | 2.793 | 2.706 | 3.467 | 39.91 MiB |
| 3時間 | 12 | 22,689,432 | 8.024 | 7.871 | 10.607 | 56.55 MiB |
| 8時間 | 32 | 60,505,152 | 21.068 | 20.648 | 27.880 | 96.78 MiB |
| 24時間 | 96 | 181,515,456 | 63.866 | 61.898 | 86.207 | 224.73 MiB |

処理秒とCPU秒は合成音声の作成後から測った。RSSは合成音声の準備も含むプロセス全体の最大値。
24時間では書き出し直後の一時ディレクトリが最大174.55 MiB、1秒間隔で採取した
プロセスの最大footprintが201.25 MiBだった。4条件とも全区間の原本時刻対応と一時領域の回収を検証した。
日本語の認識精度、推論時間、実機の連続録音、熱・電池、通信量とクラウド請求額は別の実機検証で計測する。

## 自動検査

```bash
bash tools/checks/run-audio-diagnostic-checks.sh
python3 -B tools/checks/test_audio_measurements.py
```

実Swift session/archiveの単調clock、部分区間除外、再利用、bounded保持、cache再読込、
消去/設定世代、更新順序、エラー内容非記録、Swift JSON→Python集計と、CER/WER/RTFを検証する。
時間・電池・温度はfixtureを使う。実音声の認識・本番ネットワーク・実機消費量の検査ではない。

2026-11-02の結果: 上記Swift→JSON→Python検査PASS、Pythonの5検査PASS、実PCMの
audio intelligence検査PASS、50MB超WAV/SQLite再開を含むsource extraction cache検査PASS、
実AVFoundationのsource media export検査PASS、summary reading関連検査PASS。
`git diff --check` PASS。`bitrig preview -platform iOS`成功（既存警告11件）。
シミュレーターで設定入口と空の計測画面を画像確認。アクセシビリティtree取得が失敗するため、
VoiceOver・AX操作・実測結果の表示・共有先での受け取りは未検証。

## ファイルの対応

追加したappファイルは`App/AudioDiagnosticReport.swift`（schema）、
`AudioDiagnosticEnvironment.swift`（環境）、`AudioDiagnosticSession.swift`（時間/集計）、
`AudioDiagnosticArchive.swift`（bounded cache）、`AudioResourceProbe.swift`（採取）、
`AudioDiagnosticsView.swift`（設定内の閲覧/共有）。既存`AudioProcessingDiagnostics.swift`の
signpostにopt-in collectorを追加した。

既存の接続箇所は`AudioRecorderService`、`RealtimeTranscriptionService`、
`RecordedAudioTranscription`、`SourceIntake`、`SourceMediaExtraction`、`SourceMediaSnapshot`、
`SourceMediaAudioExport`、`TranscriptionService`、`TranscriptionOutcome`、
`CloudTranscriptionService`、`FluidVoiceActivityEvaluator`、`FluidSpeakerDiarizationService`、
`AudioSignalInspector`、`AudioSignalReport`、`MeetingSummarizer`、`SettingsCategoryView`（`App/*.swift`）。

検査/集計は`tools/checks/AudioDiagnosticChecks.swift`、`audio-diagnostic-sources.sh`、
`run-audio-diagnostic-checks.sh`、`audio-measurements.py`、`test_audio_measurements.py`を追加。
既存のaudio intelligence/source extraction cache/source media export/summary reading runnerへ
共通のproduction計測型を渡すよう更新した。Project.json・依存ライブラリ・record schemaは変更しない。

高温時の区間境界制御は`AudioProcessingReadiness.swift`を追加し、`SourceMediaFailure`、
`RecordedAudioTranscription`、`SourceMediaExtraction`へ接続。audio intelligence検査でOS状態ごとの
判定、保存音声検査で実export後の停止・prefix非公開・SQLite再生成後のsuffix再開・
criticalでも完成cacheを再利用できることを確認する。温度状態と認識結果はfixtureである。

## 録音tapとライブ分離の計測（2026-11-08）

録音traceには、tapコールバックの所要時間を内容なしのマイクロ秒ヒストグラムで
`latencies["recordingTap"]`（samples, p50, p95, p99, maximum）として保存する。
直近4,096コールバックを保持し、音声・ファイル名・record IDは含めない。
ライブ側は`liveBufferDropped`（有界キューの満杯/analyzer側drop）と
`liveConversionFailure`（analyzer形式への変換失敗）を数える。どちらも録音writerの
受理・overrun・保存結果とは別で、ライブ表示だけが止まる。

### 実機で確認する手順（未実施）

1. 設定 › 診断とプレビュー › 音声処理の計測をオンにし、通常の連続録音を15分行う。
2. 同じ端末で、録音中にBluetooth接続/切断、着信→復帰、ロック、バックグラウンド、
   省電力切替、一時停止→再開を各1回行う。各操作の前後で録音が続いていること、
   `recordingTap`のp99が跳ね続けないこと、`liveBufferDropped`が録音停止に
   つながらないことを確認する。
3. 録音終了後、AACが`afinfo`で読め、15分境界の前後で連続した原本が残り、
   SQLiteのmanifestと再生時刻が一致することを確認する。
4. 計測JSONを共有し、`audio-measurements.py report`でp50/p95/p99とdropを確認する。
   端末のthermal stateがserious/criticalの区間は別条件として扱い、平均へ混ぜない。
5. 15分ちょうどの停止、rotation直後の停止、低容量、media services reset、
   強制終了後の復旧を別々に記録する。復旧は自動再録音ではなく、原本の保持と
   手動の文字起こし再開までを確認する。

シミュレータの数値はホストCPU/RSSであり、実機の電池・熱・音切れの証明ではない。
