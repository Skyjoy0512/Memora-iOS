# Ask AI追加データのバックアップ・復元検証

## 2026-11-25 媒体保護の再検証

手動バックアップから復元した録音・写真にも、通常の保存先と同じフォルダ保護・端末バックアップ除外を適用する。iOSでは配置前のコピーにファイル単位の完全保護も設定する。保護設定に失敗した場合は、媒体を配置せず、記録を保存しない。手動バックアップには従来どおり媒体を含める。[Appleのファイル保護](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files) · [端末バックアップの除外属性](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup)

ホスト回帰試験では、写真フォルダの保護拒否でSQLite保存が始まらず、音声と写真も作られないことを確認する。旧版を復元した場合は両方のフォルダが保護処理を通り、元のバイトが復元される。iOSのパスコードロック中の挙動、OSのバックアップ採否、機種変更は実機での確認が必要。

2026-10-16。`967c000`以降の継続作業。外部API、実ユーザー記録、APIキーは使用していない。

## 修正

- `BackupRestoreTransaction`をアプリの復元経路へ接続。媒体・WorkspaceFilesの配置後も、SQLiteの一括保存が成功するまでは取り消せる。親Taskの停止を準備Taskへ伝え、配置済みファイルも撤去する。
- `MemoraModel+Backup`は開始時と保存直前に検証。AI/Resident/Research/Project Chat処理中の復元を拒否し、workspace generationで個人→チーム→個人への切替も検出する。端末内バックアップの作成・復元は個人workspaceから操作する。
- `BackupPackageFile`でmanifest・media・workspaceの実ファイルを検証。ファイルだけでなく、その格納フォルダがシンボリックリンクの場合も拒否する。
- 音声/写真のコピー後にも通常ファイルであることを確認し、WorkspaceFilesは一時フォルダに全件コピーして容量・ファイル種別を再検証し、既存ファイルを置換せず配置する。途中の衝突や失敗では、その復元が配置したファイルだけを撤去する。
- 重複した資料IDと、メール下書きの宛先/CC/BCC合計100件超を拒否。SQLite保存失敗は媒体の配置失敗と区別して表示する。
- 保存形式やバックアップの版番号は変更していない。UIの配置・ナビゲーション・権限設定も変更していない。

## 検証方法

`bash tools/checks/run-backup-restore-checks.sh`。既存の`run-memory-artifact-checks.sh`および`run-next-generation-checks.sh`からも実行する。

本番の`BackupPackage`、`ProjectWorkspaceBackup`、`BackupRestoreTransaction`、新しい各データ型のCodable、実際の`LocalStore`/SQLiteをコンパイルして実行する。媒体・WorkspaceFilesの場所と従来の会議等のレコード形状のみ架空の小さなfixtureへ置き換え、実アプリの保存先には触れない。

確認した内容:

- メモリと改訂履歴、エピソード、下書き/宛先不明、企業テンプレート、編集可能な資料モデル、元記録IDを含むmanifestの書出し・再読込。
- 合成DOCX/PPTX、資料の根拠テキスト、架空の音声/写真のバイト一致。
- 新しい任意フィールドを除いたversion 1のfixtureを実際の復元経路で配置できる。
- 重複した資料ID、宛先件数超過、欠損・壊れたJSON・容量超過、パス移動、manifestのリンク、workspace格納フォルダのリンクを拒否。
- SQLite triggerで一括保存を途中失敗させ、先行したレコードの保存と配置ファイルが両方取り消され、無関係な既存レコードを保持する。
- 復元前の中断、配置済み・commit待ちでの中断、保存直前の認可ゲート拒否でcommitされない。
- 後半のファイル名衝突で前半の配置を撤去し、既存ファイルのバイトを保持する。
- 成功後にSQLiteを別接続で開き直し、各追加データとファイルを再読込できる。

## 検証の範囲

これは隔離したhost上の保存・復元テストである。iOSのSettings画面からの実復元、利用者の過去版アーカイブそのもの、ファイルプロバイダ上の操作、実機容量不足、Word/PowerPointの最終描画は未検証。workspace変更時は本番コードのgeneration判定を追加したが、このfixtureでは保存前ゲートの拒否と後片付けを検証しており、iOS画面操作のE2Eは含まない。

ビルドと既存スイートの結果は[機械可読の検証記録](ASK_AI_NEXT_VALIDATION.json)の`followups`を参照。

## 変更ファイル

|用途|ファイル|
|---|---|
|復元の一括処理と取り消し|`App/BackupRestoreTransaction.swift`、`App/MemoraModel+Backup.swift`|
|パッケージ内ファイル・識別子・件数検証|`App/BackupPackageFile.swift`、`App/BackupPackage.swift`|
|WorkspaceFilesのステージング|`App/ProjectWorkspaceBackup.swift`|
|隔離した実復元テストと既存runnerへの組込|`tools/checks/BackupRestoreChecks.swift`、`tools/checks/run-backup-restore-checks.sh`、`tools/checks/run-memory-artifact-checks.sh`|
|実装・検証記録|本書、`docs/ASK_AI_NEXT_IMPLEMENTATION.md`、`docs/ASK_AI_NEXT_VALIDATION.json`|
