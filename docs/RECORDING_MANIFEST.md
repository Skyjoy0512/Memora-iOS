# 録音manifestと原本を保持する復旧

2026-11-02。前段の[原本参照基盤](RECORDING_AUDIO_ORIGINALS.md)に、録音下書きの
順序・フレーム位置・確定状態を接続した。自動ファイルローテーションと複数原本の音声統合は
まだ有効にしていない。実機24時間録音の完了宣言ではない。

2026-11-03追補：[複数原本の端末内認識](SEGMENTED_AUDIO_TRANSCRIPTION.md)を接続した。
全原本が確定したmanifestを持つ記録は、既存の再試行から15分処理/SQLite再開を利用できる。
以下の復旧時の自動認識拒否は維持する。自動rotationと複数原本の連続再生は引き続き未接続。

同日追補：[連続再生](AUDIO_PLAYBACK.md)と[分割writerのコア](RECORDING_CHUNK_WRITER.md)を追加。
確認できた複数原本の復旧は失敗扱いから手動文字起こし待ちへ更新した。欠落/不一致の拒否は維持。
マイクへのwriter接続はまだなく、自動rotationは未提供。以下は各時点の経過記録。

## 今回接続した経路

新規録音は、これまでの下書きにoptionalな`audioManifest`を持つ。既存下書きはキーなしで読め、
従来どおり長さを確認して復旧する。新しいmanifestは録音ID、版、サンプリングレート、
原本名・開始フレーム・フレーム数・writing/finalized状態を保持する。
録音IDが欠けていてmanifestがあるときは、そのIDを維持する。

開始位置0、区間の隙間・重複なし、一意で安全な名前、最終区間だけwriting可を検証する。
現在の上限は24時間、128原本、8〜192kHz、名前255bytes。開始時は既存の録音設定と同じ
44.1kHzで1つのwriting原本を登録する。録音中メモのcheckpointもmanifestを保持し、
不整合なmanifestは上書きしない。

停止後または復旧時はAVAudioFileのメタデータからフレーム数とサンプリングレートを確認する。
全音声をPCMへ展開せず、utility taskで順次確認する。ファイル属性の前後比較、通常ファイル・
symlink拒否、取消を確認する。ただし全圧縮packetの復号や音声品質を保証する検査ではない。
内容が正しいことや認識cacheの再利用を、この確認だけで確定しない。既存の認識用snapshotと
hash照合は変更していない。

単一原本が確認できたときは、確定manifestと原本参照を保存し、従来の再生・端末内認識へ渡す。
確認不能なら長さを推測せず、原本参照とメモ・重要マークを保持する。

複数原本の下書きは、全ファイル参照とmanifestを1つの記録へ保存する。全部のフレーム数が
一致すればメタデータ上の合計長は保持できるが、復旧直後は失敗状態とし、
自動認識・要約を始めない。一部の原本を再生用audioURLへ割り当てない。
欠落・破損・確定済みフレーム数の不一致があれば、合計長を推測せず0（不明）にする。
ファイルが実在するとは言えない場合、案内も保存情報の保持だけを伝える。

復旧中のworkspace/draft/取消等の変更は公開を拒否する。既存記録とIDが衝突したときは、
manifestの時刻・レートと全原本参照の保持を確認する。Journalだけの同一IDや不整合な記録に
原本の所有権を移したことにして下書きを消さない。保存失敗でメモリ内だけに記録がある間も
復旧や破棄で下書きを消さず、既存の保存再試行を使う。

## バックアップ・削除

Meetingにもoptionalな確定/未確定manifestを保存する。バックアップは構造・記録ID・
原本参照集合との整合性を検査し、版3で保持する。音声削除/undoはmanifestも外す/戻す。
削除待ちの再試行は録音下書きの全原本を所有中として保護する。

明示的な録音破棄は、下書き削除と全原本の削除待ち登録を同じSQLite transactionで確定する。
失敗時はファイルを消さない。成功後だけ対象IDの削除を試し、別記録が使う原本は保護する。
下書きを先に消して音声だけが残る、または逆に音声だけ消える窓を作らない。

## 変更ファイル

追加（App）：`RecordingAudioPart`、`RecordingAudioManifest`、`RecordingDraftInspection`、
`MemoraModel+RecordingInspection`。
変更（App）：`RecordingAudioValidation`、`MediaFiles`、`Meeting`、`Meeting+AudioFiles`、
`MemoraModel`の下書きID読み込み、`MemoraModel+Capture/RecordingRecovery/RecordingFinalization/RecordingCheckpoint/Media`、
`BackupPackage`。新規ライブラリ、Project.json変更、クラウド送信、UI構成変更はない。

検査追加：`tools/checks/RecordingManifestChecks.swift`。
録音確定・原本管理・開始・バックアップの既存検査と、各runnerの型依存を更新。
音声取り込みrunnerの不足していた既存PDF依存も補充し、URL準備のエラー型は実コードから抽出する。

## 検査と限界

- `run-recording-finalization-checks.py`：manifest境界・隙間/重複/不正名、24h/96区間の
  メタデータ、実SQLiteでの複数原本復旧と再open、欠落/不一致で認識しないこと、
  単一原本の確定、6つの非同期反映拒否、ID衝突/未保存記録の保護、実PCM/M4Aのフレーム確認。
- `run-recording-media-checks.py`：manifestを含む明示的破棄、SQL DELETE失敗時のrollback、
  他の所有者がいる原本の保護。既存の削除/undo・保護store・容量集計も検査。
- `run-recording-start-checks.py` / `run-recording-recovery-checks.sh`：旧下書きと開始の回帰。
- `run-backup-restore-checks.sh`：manifest往復、ID/時刻改変の拒否、実ファイルの復元、旧版対応。
- `run-audio-import-checks.sh` / `run-video-transcript-checks.sh`：取り込み・codecの回帰。
- `bitrig preview -platform iOS` / `git diff --check`：iOS統合と差分確認。

上記7系統のホスト検査と差分検査は通過。最終iOS previewも成功（既存警告11件）。
ホスト検査ではモデル境界・マイク・OS割り込み・UI・認識がfixture。新しいframeCount検査は
実PCM/M4Aファイルを読むが、24時間の実録音ではない。実機のRTF/CER、境界の音切れ、
バックグラウンド連続動作、電池/発熱は未測定。

残件は録音書込のローテーション、manifestの原本切り替えtransactionと連続再生。
11月3日の追補で、確定済み複数原本の認識準備・原本時刻対応・中断後の再試行を接続した。
ファイル切り替えだけを先に有効にしない。複数原本を保持する復旧、手動認識できる記録、
連続再生まで可能な記録を区別する。
