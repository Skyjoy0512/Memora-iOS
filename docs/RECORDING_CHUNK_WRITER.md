# 連続入力用の分割書き込みコア

2026-11-03。`RecordingChunkWriter`、`RecordingRotation`、モデルのSQLite保存境界を追加した。
**現在のマイク録音は引き続き既存のAVAudioRecorderを使う。自動rotationはまだ有効ではない。**
このコアは連続PCMを受け取って原本を書き出す部分であり、マイク/sessionを取得しない。
次の単位でライブ認識と共有する入力、停止時のdrain、割り込み時の終了を接続する。

## 書き込みと保存順序

開始前に、1原本/writingのmanifestと下書きを永続保存しておくことが呼び出し側の条件。
入力は44.1kHz・mono・非interleaved Float32 PCM。hardware formatからの変換は入力側の責任。
最大16,384フレーム/バッファ、待機16バッファのstreamへ所有コピーを渡す。
単一consumer taskが順序どおりAAC（96kbps）を書き、15分の境界でバッファを分配する。
コア内で全録音PCMを保持しない。このcodec設定を既存録音へ適用したわけではなく、
精度/処理時間/電池の評価後に本番接続を判断する。

原本を閉じ、AVAudioFileで実フレーム数・レート・channel数を確認してから切り替えを申請する。
`RecordingRotation`は以前のmanifest、直前の確定フレーム数、次の安全な原本名から作る。
隙間/重複・24時間超過・128原本超過・不正名を拒否し、改変された申請を再構築比較で拒否する。

`admitRecordingRotation`はworkspace世代、個人workspace、録音/保存中、下書きID、
現在の原本参照、以前のmanifestの完全一致を確認。既存ファイル名との衝突も拒否する。
現在のメモ/マークを含めた下書きと次のmanifestを、既存のserial storeの同期commitで保存し、
成功後だけメモリ内のdraft/recordingURLを更新する。先にenqueueされたcheckpoint書込は
このcommitより後に到着しない。呼び出し側はこの結果をwriterのadmission callbackへ返す。

writerはadmissionが成功してから次のファイルを排他的に新規作成し、書き込みを始める。
既存原本を上書き/削除しない。ちょうど15分で入力が終わる場合は空の末尾原本を作らない。
新しいファイルを作る前と256入力ごとに空き容量を確認。256MiB未満や原本合計2GiB超を拒否。
入力frontendには、既存の15秒容量監視も維持する必要がある。

`append`がfalseを返したら入力側は録音を止める。満杯時に入力を黙って捨てて成功扱いにしない。
正常終了はproducerを停止後に`finish()`で受理済み入力をdrainし、確定manifestを受け取る。
取消はtaskも失効させ、admission待ちから戻った後に新しい原本を書き始めないようにする。
書込み/容量/保存/上限/形式/取消の失敗は結果へ返し、失敗結果を完成と扱わない。

admission成功後、次ファイル作成前に停止すれば、下書きに未確定/欠落の末尾参照が残り得る。
現行の復旧は全参照を保持し、不明な長さや完成状態を推定しない。末尾予約の修復と
確認済みprefixだけの救出は今後の接続で扱う。SQLiteと音声ファイルを一つのtransactionで
書ける、あるいは電源断時もAACが必ず開ける、と保証する設計ではない。

## 確認できた複数原本の復旧

再生/認識のmanifest経路が実装されたため、全原本の長さが確認できた複数原本は、
復旧後に既存の「文字起こしする」へ進めるよう判定を更新した。復旧直後の自動認識は行わない。
通常保存では確認できた音声を既存の処理経路へ渡す。欠落/不一致は引き続き失敗として保持する。
一部分のaudioURLを全体とみなすことはない。

## 実マイク入力の所有（未接続）

2026-11-07。`RecordingMicrophoneInput`を追加した。録音runごとに1つの`AVAudioEngine`
入力tapを所有し、`inputNode`の実`outputFormat`（44.1kHzを仮定しない）を読み、
`LiveAudioBufferConverter`で44.1kHz/mono/非interleaved Float32へ変換する。
セッションは`AudioRecorderService`が取得済みのものを共有し、独自sessionや2つ目のtapを作らない。
tapは変換と受け渡しだけを行い、ファイル・SQLite・UI処理をしない。所有bufferを
recording sinkへ先に渡し、成功後にlive sinkへ渡す。sinkがfalseを返したら入力を止め、
満杯を成功扱いにしない。通算位置は受け取った変換後フレームから求める。

`RecordingInputContinuity`がtapの`when.sampleTime`を前回の終端と比較し、欠落を`gap`、
重複を`duplicate`として検出する。sampleTimeが無効な端末では検査不能として扱い、
推定で穴を埋めない。`RecordingChunkWriter`側の16,384フレーム上限と16バッファ待ちが
そのまま適用される。

**まだ`startCapture`には接続していない。** `RecordingMicrophoneInput.start()`は
共有sessionがactiveな後にだけ呼ぶ必要があり、実マイク->writer、開始前manifest永続化、
停止drain、自動rotationは次の小タスクで接続する。`AudioRecorderService`の通常録音は
引き続き`AVAudioRecorder`を使う。検査は
`bash tools/checks/run-recording-microphone-input-checks.sh`で、44.1kHz/mono形式、
gap/duplicate/empty判定、48kHz・stereoの変換、所有コピーをhostで確認する。
AVAudioEngineのtap開始/停止と実機音声は未検証。

## 録音runの状態保護

2026-11-07。`RecordingRunCoordinator`を追加し、`AudioRecorderService`の通常録音へ接続した。
idle → preparing → recording → stopping → finalizing → saved をrunID付きで管理し、
二重start/stop、古いcallback、準備中の取消、media servicesのresetを明示的な失敗へ落とす。
失敗・取消・保存済みのあとは次のrunを開始できる。`stop()`の二重呼び出しはfinalizing以降を
再遷移させない。`hasReportedFailure`の代わりにrunのphaseで重複した割り込み通知を拒否する。

この範囲は**音声キャプチャのライフサイクル**であり、記録のSQLite確定は従来どおり
モデル側の`stopCapture`→`commitRecordingSave`が担う。実マイク→writerの接続、停止drain、
自動rotationはまだ有効ではない。新しい検査は
`bash tools/checks/run-recording-run-coordinator-checks.sh`で、状態遷移・二重操作・
古いrunID・各段階の失敗・取消をhostで確認する。既存のchunk writer/start/media/recovery/
extraction cache各検査と`bitrig preview -platform iOS`も通過した（既存警告のみ）。
実機の割り込み・二重操作・24時間動作は未検証。

## 計測・検査の状態

任意の既存diagnostic sessionへ保存待ち時間、確定区間数、書込み済み音声秒数を通知する。
音声本文、原本名、record ID、pathは診断reportへ渡さない。
core自体はsessionを開始/終了せず、将来接続するrecorderがその寿命を管理する。

`bitrig preview -platform iOS`は成功、プレビュー更新済み（既存警告11件）。
ユーザーの指示により、今回のhost/実機検証は実行していない。
新しい検査コードは`bash tools/checks/run-recording-chunk-writer-checks.sh`で実行予定。
短い区間を使い、実AACのフレーム分配、境界終了時の空ファイル防止、admission拒否、
既存原本の排他的保護、24h/96原本のmanifest計画を検査する。検査用の短区間設定でも
本番上限の15分を超える設定は受け付けない。
既存`RecordingManifestChecks`の完全な複数原本復旧の期待値も更新したが未実行。

実マイク、AAC priming/flushのフレーム整合、境界の音切れ、過負荷、取消/停止/割り込み、
SQLite rollbackとcheckpoint競合、24hの電池/熱/メモリ、RTF/CERは未検証。
このビルドを24時間録音対応の完成や性能測定と扱わない。

## 変更ファイルと次の接続

追加：`App/RecordingChunkWriter.swift`、`RecordingRotation.swift`、
`MemoraModel+RecordingRotation.swift`、`tools/checks/RecordingChunkWriterChecks.swift`とrunner。
変更：`RecordingDraftInspection.swift`、`MemoraModel+RecordingInspection.swift`、
`tools/checks/RecordingManifestChecks.swift`。新規ライブラリ・Project.json・UI配置の変更なし。

残件は、原本作成前のdraft保存、共有マイク入力/変換、liveへの分配、writerへの失敗通知、
停止時drain後の確定、通算録音時計、既存checkpoint監視の世代管理、復旧と削除との協調。
マイク経路を接続するまでは新writerのcallbackを既存AVAudioRecorderに結び付けない。
