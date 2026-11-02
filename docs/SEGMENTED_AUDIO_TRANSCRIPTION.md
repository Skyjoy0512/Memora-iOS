# 複数原本の端末内文字起こし

2026-11-03。確定済みmanifestを持つ複数原本の記録を、既存の「再試行」から端末内で
文字起こしできるようにした。録音中の自動rotation、複数原本の連続再生、実機24時間の
完了を意味しない。UI、録音原本、既存の単一ファイル認識を保持する。

## 入力と時刻

`RecordedAudioInput`が単一ファイルとmanifest入力を共通の認識経路へ準備する。
複数原本は全区間がfinalizedで、記録ID・順序・フレーム位置・長さの整合するmanifestが必要。
通常ファイルであることを検査し、symlink・未確定・欠落・不正な入力は認識前に拒否する。

既存の`SourceMediaSnapshot`で各原本を不変コピーし、内容hashを確認する。
AVAudioFileのフレーム数・サンプリングレートがmanifestと完全一致し、全原本のchannel数が
同じ1〜2chであることを確認する。音声trackが1つ、開始時刻0、宣言した長さを収容できる
入力だけを扱う。自動補正や推定時刻による穴埋めはしない。

`AVMutableComposition`に原本フレーム単位のCMTimeで配置する。24時間分を結合した
新しい音声ファイルやPCM配列は作らない。既存の最大15分のAAC exportだけを順に生成し、
認識結果を元録音の通算時刻へ戻す。manifest上限は24時間/128原本、今回の一時コピーの
入力合計は2GiBまで。初回予約だけでなく、各コピー直前にも合計サイズと空き容量を確認する。
コピー上限をその時点の原本サイズに限定し、処理中の増大で他区間の予約を消費しないようにする。
容量不足時は原本を保持して失敗を返す。古い原本の自動削除はしない。

## 再開・反映・クラウド

`RecordedAudioTranscription`の既存15分処理、SQLite完了prefix、thermal待機、取消、数値計測を
再利用する。複数原本のcache keyは全原本hash・順序・フレーム位置/数・sample rateと、
既存の言語・用語集・pipeline版を含む。単一ファイルの旧cache keyは維持する。
途中失敗ではprefixを完成結果として返さず、次の明示的な再試行で未完了区間を再処理する。
完成cacheを使う場合も含め、返却前に全原本の属性と内容hashを照合する。

モデルは開始時・非同期待機後・外部送信許可時・結果反映時に入力参照とmanifestを再確認する。
既存のworkspace世代、privacy、取消、transcript revisionの確認も維持する。
音声参照やmanifestが変わった古い処理結果を適用しない。

複数原本の認識はSpeechAnalyzer経路に接続する。設定でクラウドを選んでいる場合は、
送信許可のcallbackやproviderを呼ぶ前に拒否し、端末内設定での再試行を案内する。
分割送信、同意付与、クラウド利用枠消費を新たに有効にしていない。

## 検査

- `bash tools/checks/run-source-extraction-cache-checks.sh`：実WAV 450秒+451秒からの
  native composition/AAC export、原本境界前後の440/880Hz相関、15分境界後の時刻、
  続きの失敗と新しいSQLite storeからの再開、完成cacheを検査。同じsize/mtimeでの
  内容変更、認識中の原本変更、未確定manifest、フレーム不一致、symlink、合計容量超過を拒否。
  実M4A 2本の配置・再exportも検査し、stage削除と原本保持を確認する。
- `python3 -B tools/checks/run-recording-media-checks.py`：実Meetingの認識対象判定、
  未確定/別IDのmanifest拒否、入力metadata変更の検出、無関係なnotes変更の許容と、
  既存のSQLite削除/undo/rollback・他記録/下書きの原本所有保護を検査する。
- `bitrig preview -platform iOS`：アプリを統合ビルドし、プレビューを更新する。

上記2系統のホスト検査と`git diff --check`は通過。iOS previewも成功（既存警告11件）。
検査中、原本名の配列を反転して変更を作るfixtureが回文配列だったためassertionが失敗した。
異なる要素の入れ替えに直し、関連検査全体が通過することを確認した。

ホストの認識callbackはfixtureであり、SpeechAnalyzerの実認識や音声品質検査ではない。
901秒の実ファイルを使う検査を、24時間の実測と扱わない。RTF/CER/DER、実iPhoneの熱・電池・
メモリ、バックグラウンド割り込み、モデル非同期処理と実UIの一体動作は未検証。
既存のopt-in計測を使って実機で測定する。削減時間やVAD節約額の実測値はまだない。

## ファイルと次の作業

追加：`App/RecordedAudioInput.swift`、`tools/checks/SegmentedAudioTranscriptionChecks.swift`。
変更：`App/RecordedAudioTranscription.swift`、`TranscriptionService.swift`、`Meeting+AudioFiles.swift`、
`MemoraModel+Processing.swift`、cache検査runner/entrypoint、`RecordingMediaChecks.swift`。
新しいライブラリ、Project.jsonやSQLite schemaの変更はない。

復旧直後は従来どおり自動認識を始めず、確認済み複数原本を保持した記録の再試行から使う。
未確定や欠落した原本の再検査/修復はこの経路では行わない。
次は録音書込の安全なrotationとmanifest更新の一括確定、連続再生/seek、引用からの音声移動を
接続する。全原本のsnapshotに必要な一時空き容量の削減と、2GiBを超える記録の扱いも残件。

同日追補：連続再生/seek/引用時刻の実装を接続した。[再生の実装記録](AUDIO_PLAYBACK.md)。
ユーザーの指示により、この再生改修のhost/実機検証は後へ回している。
