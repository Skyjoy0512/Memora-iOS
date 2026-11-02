# 分割録音に向けた原本参照と保存基盤

2026-11-02。分割録音を有効にする前段として、保存済みの1記録が複数の原本を保持できる
ようにした。録音機能は引き続き単一ファイルであり、この変更だけでは24時間録音を保証しない。

## 保存と互換性

- `Meeting.audioURL`は既存の再生・認識用の単一音声のまま維持する。
- `originalAudioFileNames`はRecordingsフォルダ内の原本名の配列。音声bytesをSQLiteへ
  埋め込まない。旧記録では空配列、保存時も空ならキーを追加しない。
- 管理対象の解決と重複排除を`Meeting+AudioFiles`に集約。原本の名前と並びは保存時に
  勝手に変更せず、バックアップ検証では生の参照を確認する。
- 一時的に解決できない旧音声の`rawAudioReference`も、ノート等の保存で失わない。
  明示的な音声削除では解決済みURL・生参照・分割原本参照をすべて外す。
- この配列は時刻対応表ではない。チャンクの時刻・フレーム数・確定状態は次の録音manifestで
  別途管理する。部分原本だけを完成音声として再生・文字起こしする経路は追加していない。

アプリの変更ファイルは`Meeting.swift`、`Meeting+AudioFiles.swift`（追加）、`BackupPackage.swift`、
`MemoraModel+Media.swift`、`MemoraModel+Trash.swift`、`MemoraModel+Journal.swift`、
`StorageUsageView.swift`（すべて`App/`）。既存のSQLite、削除待ち台帳、undo、backup stagingを再利用。

## バックアップ

再生用音声と全分割原本を必須ファイルとして収録する。複数記録や同じ記録が参照する同じ
ファイルは1回だけコピー・列挙する。ファイル欠落、不正な名前、symlink、通常ファイル以外を
拒否し、原本を欠いたバックアップを成功扱いにしない。コピーはファイル単位で、全音声を
Dataへ読み込む処理は追加しない。

分割原本がある場合だけmanifest版3で書く。原本を知らない旧アプリが受け入れて参照を落とす
ことを避けるため。通常の記録は従来の版2で書き、旧版1/2の読み取り・復元も維持する。
復元時は既存の全参照検証、競合時の上書き拒否、staging、失敗時rollbackを再利用する。

## 削除と取り消し

既存の「音声を削除」と90日より前の一括削除に原本を含める。記録から参照を外す更新と、
削除待ち台帳への登録を同じSQLite transactionで確定してから公開する。取り消しも参照復元と
台帳からの除外を一括保存し、途中で編集したノート等は巻き戻さない。台帳の保存形式は変更せず、
既存の1音声参照の項目をファイルごとに使う。

削除確定・ゴミ箱の完全削除・期限切れ処理は、その操作が登録した台帳IDだけを処理する。
別の取り消し待ちを巻き込まない。起動時の台帳再試行は従来どおり全件を対象にする。
現行記録、ゴミ箱内の記録、録音下書きが参照する音声を確認し、他の所有者がいるファイルは
削除しない。削除失敗時は台帳に残し、store保護中は削除しない。

保存容量の既存画面は、各記録の再生用ファイルと重複しない原本のサイズを合計する。
画面構成や文言・操作の追加はない。原本の自動削除ポリシーは追加していない。

## 検査

- `python3 -B tools/checks/run-recording-media-checks.py`: productionのMeeting codec、
  Media/Trashの操作、Journalの完全削除、パス判定、容量集計と実SQLiteを使用。
  旧記録、未解決生参照、複数原本、重複、削除/undoのSQL ABORT・再open・一括保存、
  他のundo待ち保護、共有原本/下書き/ゴミ箱の参照、期限切れ、保護中、パス逸脱を検査。
  写真API、undo表示タイマー、modelの永続化adapter、無関係な型とファイル削除の失敗注入はfixture。
- `bash tools/checks/run-backup-restore-checks.sh`: productionのMeeting codecも使い、
  版3の全原本コピー・復元・重複排除、欠落/パス逸脱/symlink/版違いの拒否を追加。
  既存の版1復元、版2、実SQLiteのrollback/reopen、取消・競合保護も検査する。
- `python3 -B tools/checks/run-recording-finalization-checks.py`: 録音終了・復旧・保存再試行と
  checkpointの既存検査。音声認識、マイク、UI、OS schedulingはfixture。
- `bash tools/checks/run-person-journal-checks.sh`: Journal CRUD・ゴミ箱・privacyの既存検査。
- `bitrig preview -platform iOS`と`git diff --check`。

ホスト検査とiOS previewは成功（既存警告11件）。`git diff --check`も通過。実機の連続録音、分割録音の
音声連続性、電池/thermal/RTF/CERは未検証。実機やクラウドへ音声を送った検査ではない。

## 次に接続する範囲

録音下書きに対する順序・原本時刻・確定状態を持つmanifest、録音書込のローテーション、
中断時の複数原本復旧、単一の再生/認識用音声への安全な統合またはmanifest再生、
容量不足時の動作を一体で接続する。現在のRecordingDraftは単一原本のままなので、
この基盤だけを使って先に録音を分割してはいけない。原本の保全と時刻を証明した後に有効化する。
