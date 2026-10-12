# Project Workspace V2 — 共有からの取り込み

## 現在の状態

Share Extensionターゲット、標準の保存先Picker、URL・画像・ファイル・テキストの受信、本体の取り込み処理と回復画面を追加した。現在はApp Groups未設定のため、共有保存は利用できない。未接続と明示し、通常のアプリ内ソース追加は引き続き利用可能。

現在のscaffold bundle IDを維持した。識別子変更を理由に既存インストールのSQLiteや音声を見えなくしない。署名・App Group登録・実際のSafari／写真／ファイルアプリからの共有は未確認。

## 接続に必要な設定

1. 既存インストールのバックアップ／復元を確保してから、Bitrigのasc_assign_bundle_idで恒久IDを割り当てる。既存データを同じコンテナから自動的に移せると仮定しない。
2. 恒久ホストIDを基に `group.<host-bundle-id>` をApple DeveloperのApp Groupとして登録する。Share ExtensionのIDはホストに `.share-extension` を付けたものに整合させる。
3. Project.jsonのホストと共有拡張に、同じ `com.apple.security.application-groups` entitlementを追加し、両ターゲットのInfo.propertiesの `MemoraShareAppGroup` に同じ値を指定する。生成されるInfo.plistやentitlementsを直接編集しない。
4. App Groupを含むProvisioning Profileで署名し、本体を一度開いてプロジェクト候補を更新する。シミュレーターでのビルドだけを署名接続の証拠にしない。

現在のProject.jsonにはApp Groupを登録済みと装うentitlement／Infoキーを入れていない。共有拡張は未接続画面を表示する。ShareInboxConfigurationは恒久IDから派生したGroup名との一致とcontainerURLの取得を確認してからアクセスする。

## 保存と回復

Shared/ShareInboxの共通コードを本体と拡張でコンパイルする。SQLite本体やAPIキー、録音・チャット履歴を拡張へ公開しない。共有するのは個人プロジェクトのID・表示名と受信キューだけ。候補は最近使用した順を先頭に最大1,000件、名称は200文字まで。チームの閲覧専用プロジェクトは候補に含めない。

拡張はproviderの一時URLが有効なコールバック内でファイルをコピーする。`.partial-UUID` にファイルとmanifestを用意し、完成したディレクトリだけUUID名へrenameして公開する。途中のディレクトリを本体は読まず、24時間より古い下書きは本体が清掃する。1ファイル50MB、1共有100MB／10項目、manifest 2MBまで。保留20リクエスト・合計500MBを検査するが、複数プロセスが同時保存する場合の合計容量予約はまだ行っていない。

本体の起動／前面復帰で、個人ワークスペースの受信を順に取り込む。リンクは既存ProjectSourceURLで公開HTTPSへの正規化・危険URL拒否を行う。ファイルは既存ProjectSourceFilesで原本をコピーし、URL／内容指紋の重複を再利用する。テキストは既存のJSON本文形式で保存する。ソースのIDにキュー項目IDを使い、SQLite確定直後にプロセスが終了しても同じ項目を二重生成しない。全項目を本体へ保存できたリクエストだけ受信キューから削除する。

削除済みプロジェクト、容量不足、書き込み失敗ではキューを残す。設定 › 共有からの取り込みで保存先を選び直し、再試行・未取り込みの削除ができる。取り込みエラー時にはプロジェクト一覧からも回復画面を開ける。キュー削除は元アプリや取り込み済みソースを削除しない。

原本保存後のPDF抽出・画像OCR・YouTube情報取得は既存のprepareProjectSourceを使う。共有だけで有料AIを呼ばず、外部AIの許可も自動付与しない。音声共有は音声ソースとして原本を保存／プレビューする段階で、既存Meetingへの変換・文字起こし開始は未接続。通常の音声取り込みと録音経路は変更していない。

## 制約と検証

Bitrig iOS Simulatorビルド成功（2026-10-13T07-53-39-9add9047.log）。新しい共有拡張もビルド／埋め込み対象。AppIntentsを持たない共有拡張のメタデータ抽出スキップ警告が1件あり、SwiftのSendable警告は修正した。iPhone 18 Pro Maxで設定から「共有からの取り込み」を開き、App Groups未設定時に接続済みと表示しないことを確認。

ShareInboxChecks成功: 公開前の不可視性、公開後の再オープンと本文保持、未完了下書き、パス／symlink拒否、不正スキーム、50MB超過、10項目超過、破損manifestの隔離、対象だけの削除。これはApp Groups越しの本体・拡張E2Eではない。

まだ確認できていないもの: 署名済みApp Group、実共有のNSItemProvider形式差、保存中の拡張強制終了、本体の保存先変更・部分成功からの再試行、実機の容量不足、VoiceOver。壊れた公開manifestはエラーとして保管し、正常なパッケージの取り込みは継続する。回復画面から破損したものだけを明示的に削除できる。受信キューは本体バックアップに含めないため、バックアップ前に本体で取り込みを完了する。
