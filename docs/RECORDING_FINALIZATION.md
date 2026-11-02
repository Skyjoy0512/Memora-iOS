# 録音終了時の音声確認と保存

2026-11-02。24時間録音の安全化に向けた保存・復旧の改修。
録音ファイルのローテーションや実機24時間稼働を実装・検証したものではない。

## 変更した動作

以前の通常終了は、ファイルの長さを取得できなくてもAVAudioRecorder/UIの時間へ
フォールバックし、さらに最低1秒として自動文字起こしへ進んでいた。
中断からの復旧では確認できない長さを0として保持していたため、判定が一致していなかった。

通常終了と復旧で`RecordingAudioValidation`の同じ数値基準を使う。
確認できた有限・正の長さを保存し、0.25秒なら0.25秒のまま扱う。
確認できなければ0を「未確認」として保存し、既存の「要確認」状態へ進める。
文字起こし・要約は自動開始しない。本文は生成せず、元ファイル参照・タイトル・
メモ・カレンダーID・重要マークを保持する。長さが不明なら重要マークを終端で切り落とさない。
元ファイルが存在しない場合は、存在すると主張しない案内を保存する。

`MediaFiles.duration`はsecurity scopeを扱い、regular/non-symlink/非空のファイルについて
AVFoundationの再生可能フラグ・音声トラック・duration metadataを確認する。
音声全体をメモリへ読み込まず、音声を書き換えない。
これはコンテナmetadataの確認であり、全圧縮packetの復号・音切れ・認識品質の証明ではない。
後続の文字起こしは既存の不変snapshot・fingerprint・15分export・checkpoint検証を使う。

Live Activity終了待ち/音声確認後に、workspace世代・draft・ファイル参照・取消・
復元中・store保護・別録音の開始を再確認する。古い処理は記録やAIジョブを追加しない。
同じdraft IDの記録/Journal項目が先に存在する場合も二重作成しない。
保存再試行では、書き込み待ち中にworkspace/draft/navigationが変わったら古い完了UI/AI処理を出さない。
一度キューへ渡したSQLite transactionの取下げを保証する設計ではない。
完了済みの個人用ローカル保存は保持し、後続のUI副作用を抑止する。

記録・Journal・draft削除は従来の単一SQLite transactionを維持する。
保存失敗時は既存の未保存録音alert/再試行を使う。再試行は同じ記録を保存し直し、
音声の再確認や録音の再開をしない。確認できなかった記録を保存できた後も、AIを自動開始しない。
record schema・既存データ・Library/Journal/Ask AI/Marketplaceや作成導線は変更していない。

## 計測

既存の初期オフの音声計測に`recordingFinalization` traceを追加した。
`verification`は音声metadata確認、`persistence`は既存SQLite transactionの待ちを含む保存時間。
確認不能な音声を保存したtraceはfailedとなり、全体RTFを出さない。
元音声時間は確認できた値だけを記録する。タイトル・note・ファイル名・record ID・
エラー内容は数値ログへ追加しない。

このtraceは録音停止後の確定処理であり、録音・認識・要約の全工程のRTFではない。
ローカル集計CLIも新kind/stageを扱う。[計測全体の手順](AUDIO_MEASUREMENT.md)。

## 検査結果

2026-11-02、以下すべてPASS。

```bash
python3 -B tools/checks/run-recording-finalization-checks.py
bash tools/checks/run-recording-recovery-checks.sh
python3 -B tools/checks/run-recording-start-checks.py
bash tools/checks/run-audio-diagnostic-checks.sh
python3 -B tools/checks/test_audio_measurements.py
```

finalization検査はproductionの終了/完了/再試行コード、Meeting/Journal codec、実SQLiteを使う。
確認したのは10種類のduration、10の確認待ちrace、Live Activity待ちrace、二重stop、
SQL ABORT→再試行→再open、欠落音声、project削除時の未分類保存、再試行中のworkspace変更、
数値ログの成功/失敗・確認/保存時間・原文非記録とPython集計への接続。
実AVFoundationでは0.25秒WAV・不正/空コンテナ・symlink・directory・欠落ファイルを確認した。
fixtureの24時間durationは数値と保存形式の検査であり、24時間録音の実績ではない。
マイク・Live Activity・確認待ちのschedule・推論・UIはfixture境界である。

既存recoveryは8 duration・11 raceと保存/再開、startは24の古いcontext境界と
正常/二重開始・許可拒否・取消を確認した。iOS 27.2 SDKの`bitrig preview -platform iOS`成功、
既存警告11件。実機動作・VoiceOver・共有先でのJSON受信はこの検査に含めていない。

## ファイル

新規: `App/MemoraModel+RecordingFinalization.swift`、`App/RecordingAudioValidation.swift`、
`tools/checks/RecordingFinalizationChecks.swift`、`tools/checks/run-recording-finalization-checks.py`。

変更: `MemoraModel+Capture`（終了処理をextensionへ分離、完了/再試行guard）、
`MemoraModel+RecordingRecovery`（共通の判定/案内）、`MediaFiles`（metadata確認）、
`AudioDiagnosticReport`（kind/stage）、`AudioDiagnosticsView`（メモリ数値変換のclamp）、
既存のrecovery fixture/runner、start runner、`audio-measurements.py`と関連文書。

## 残件

録音中のファイルローテーション、連続時刻manifest、チャンク統合再生・backup・原本export、
live確定区間の再利用、実機の強制終了/着信/OS停止/低容量/24時間録音は別途必要。
読めないM4Aを自動修復する機能も追加していない。原本を保持して確認を求める。
端末内RTF/CER/電池/thermal、VAD/NSの品質比較、クラウド実usage/原価は未測定。
