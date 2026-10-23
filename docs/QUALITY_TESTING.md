# 品質チェック

## ローカル実行

```sh
bash tools/checks/run-quality-checks.sh --list
bash tools/checks/run-quality-checks.sh --output-dir /absolute/external/path/new-results
bitrig preview -platform iOS
```

出力先はリポジトリ外の**新規**ディレクトリを指定する。既存ディレクトリは
symlinkや既存ファイルを上書きしないため拒否する。指定しなければ
`MEMORA_CHECK_ROOT`、`TMPDIR`、OSの一時保存先の順で新規作成する。
相対パスは呼出元の作業ディレクトリ基準で解決し、子の一時保存先は絶対パスに統一する。
このMacではWorkspaceSSD上の検証保存先を環境変数で指定する。

各スイートのログと`summary.json`を保持する。終了コード0は全スイート成功、
1は失敗・時間切れ・未実行がある場合、2は設定エラー。各スイートは20分で
時間切れとなる。失敗後も独立スイートを実行し、実際の結果だけを記録する。

## 検証範囲

| スイート | 範囲 |
| --- | --- |
| next-generation | 実Swift domain処理、SQLite/バックアップ、権限・人物・workspace、会話復元、MCP/OAuth、Office生成・出典、HTTP/CloudAgentSession fixture、構造化UI |
| design-refresh | 現行サイドメニュー・右上作成・モノトーン・44pt/文字・設定の静的契約、Markdown、motion/loading/cancellation |
| background-summary | 背景処理の設定とジョブ保存形式 |
| composer-layout | 日本語/絵文字・長文の入力欄寸法規則 |
| optimization | 保存失敗・録音buffer・派生index・プロジェクト検索・データ操作・既存性能fixture |

next-generationから既に呼ぶbackup/person等を重複して列挙しない。
ホストでは一部のSwiftUIをiOS SDKに対して型検査するが、完全なアプリの
リンク・拡張・リソースはBitrig Debug/Releaseビルドで別途確認する。
Project.jsonにはXcodeのテストターゲットがなく、`bitrig test`成功とは報告しない。

`run-project-source-preparation-checks.sh`はnext-generationから実行する。
本番のYouTube/ローカル解析orchestrationを待機させ、source・privacy・workspaceの
変更後の保存拒否、実file/SQLiteの後始末・再読込・再試行を確認する。
通信・抽出・downsampleのpayloadとmodel stateはfixtureであり、
実YouTube応答や端末PDF/OCR/画像品質を確認したものではない。

`run-project-source-web-recovery-checks.sh`はWeb取得の本番保存/再読込と、
実行者のいないprocessing状態の整理を検証する。実ファイル書込直後にも待機し、
失効後のファイル回収とoperation所有権、SQL失敗時の整合性を確認する。
DNS/HTTPはfixtureで、起動/再起動hook自体は別のUI E2E
`project-source-interruption.e2e.ts`で専用SQLiteへ中断状態を置いて確認する。

`run-project-source-import-checks.sh`は登録前のcontextを保持し、取込前・実copy待ち・
転送完了後・登録後の32 race、重複排除、登録済みファイル保持、同期操作の拒否と
実SQLite失敗/再読込/再試行を検証する。解析・音声・model stateはfixture。
PhotosPicker自体をホストで動かした検証ではない。

`run-audio-import-checks.sh`は本番の音声取込・URL受付・録音中の取込待機・Inboxを
実行する。8 raceとプロジェクト削除時の未分類保存、SQL失敗/再試行、読取不能時の
原本保持を実ファイルと本番Meeting codec/SQLiteで確認する。duration/media service、
navigation/model stateはfixtureで、実AV読取・再生・マイク・録音復旧を代替しない。
ホストのInboxは必須の隔離パスへ向け、製品のDocuments/Inboxは変更しない。

UI E2Eは既存`e2e`スキルの手順で実行する。テスト専用Simulatorへ
再インストールするので、Bitrigのユーザープレビューや実端末では実行しない。
`tests/ui-helpers.ts`の再起動は同一シナリオ内の永続化確認に使う。
APIキーを環境から外し、モデル呼出を含まないテストを選択する。
テレメトリーも無効にする。失敗・skip・未実行は成功に合算しない。
`project-source-pickers.e2e.ts`はnative写真/ファイルPickerの起動・取消と入力保持を
確認する。写真Pickerの一時的なLoading画面ではなく、実際の写真タブを待って操作する。
選択写真の転送やOCR成功を確認したという意味ではない。

`project-source-photo.e2e.ts`は専用Simulatorの既定写真を実際に選び、PhotosPickerの
FileRepresentation転送・SQLite保存失敗・同一写真の再選択・SHA重複排除・再起動後の
原本保持を検証する。唯一のUI作成markerで特定したSQLiteだけに一時的な失敗triggerを
置き、finallyで回収する。画像OCRは本番Vision経路を通すが、既定の風景画像1枚で
任意の写真の認識精度を保証しない。実ユーザーの写真や実アカウントは使わない。

`capture-audio-picker.e2e.ts`はLibraryの右上作成から音声Pickerを開いて取り消し、
Libraryと既存のメモ作成・取消のmorphをLight/Darkで確認する。プロジェクト詳細の
専用作成操作とは区別し、実音声の選択・再生は含まない。
対応するhost AudioImportChecksは、表示前contextを使う本番importPickedAudio入口で
8つの選択待ちraceとnil contextの拒否を追加し、正常な個人/プロジェクト保存も確認する。
ソース登録のローカルエラー処理は同期storeProjectSourceだけを囲む。await越しに
全体の失敗通知を抑えないことも実SQL失敗で検証する。

同じAudioImportChecksは本番`beginBackupRestore`も実行する。16のbusy状態、
team/protected/nonemptyとキャンセルの拒否、実音声copy後のduration待機中の復元拒否、
復元受付時の世代更新とフラグ解除後の旧Picker拒否を確認する。バックアップのエラー型、
空判定とmodel stateはfixtureであり、復元完了はフラグ解除としてモデル化する。
本番BackupPackage/BackupRestoreTransactionとSQLiteのrollback/再読込は別の
`run-backup-restore-checks.sh`で検証する。実復元とnative音声の同時UI E2Eではない。

`run-notion-service-checks.sh`はnext-generationから実行する。本番NotionServiceの
POST/PATCH組立、100 block分割、会議に属するタスクだけの送信、HTTPエラー、
通信失敗、キャンセル、トークン/保存先変更・解除、明示的再接続を確認する。
create/append応答を実際に非同期で待機させ、解除/キャンセル後に後続を送らず、
作成済みページのID/URLを保持することも検証する。自動再作成/自動retryはしない。
Meeting/formatting、設定供給、HTTP transport/応答はfixture、タスク型とサービス本体は本番。
Keychain・実UserDefaults・実URLSession/ネットワーク・実Notionにはアクセスしない。
HTTP 401/403/404/429/500/502は各段階の模擬応答であり、実認証/料金上限の証明ではない。
既存呼出先のエラー表示は維持するが、Notionエラー画面の実サービス視覚確認は含まない。

`run-gmail-service-checks.sh`は本番GmailServiceを、設定/Keychain/browser/時計/HTTPの
差し替え境界で実行する。解除リクエスト待機中の新規読取拒否、削除失敗時の解除markerと
サービス再生成、再接続後の古いtoken/list/detail応答・invalid_grantの破棄、接続中に開始した
旧アカウント読取の失効、古い認証callbackと新しい処理の所有権を確認する。
callback/PKCE、返却scope、ID/JSON、401/403/404/429/5xx、期限切れ/timeout/cancelも検証する。
Notionと同じ`HTTPResponseGate`を使い、sleepなしで非同期の応答を保持する。
本番の記憶/状態遷移/HTTP構築/解析は通すが、実Keychain/UserDefaultsやプロセス再起動、
実URLSession/Google、ASWebAuthenticationSessionの表示/取消は通さない。
fixtureの解除marker保持は実ディスク保存の耐久性検証を意味しない。
HTTP 401でaccess tokenだけを捨て、次の明示的な読取でrefresh可能なことも確認する。
Googleへの失効要求に失敗しても端末側は解除済みのままで、Google側の失効完了とは区別する。

`gmail-connection.e2e.ts`はOAuth client ID未設定のこのビルド用。
Toolsから実Gmail設定を開き、理由表示・接続ボタン無効・連携アカウント不在をLight/Darkで
確認する。認証操作や偽tokenの投入は行わない。将来client IDを設定した場合は、
この未設定ビルド用期待値を別環境へ分離し、誤った期待に合わせてアプリを戻さない。

`run-gmail-agent-checks.sh`は本番Gmail取得extension、共有会話binding、Gmail結果grant、
GmailService、Registry/会話ループ、連携ON/OFF操作を実行する。
承認/refresh/一覧/先頭metadata/full本文の各待機点で、cloud 14変更・compact 13変更、
計135 raceを検証。先頭metadataで失効した場合は2件目を取得せず、古い件名/本文を
traceへ入れない。取得後31ケース（grant消失/未知IDを含む）、24件上限、後続呼出し拒否、
batch/応答待機中の失効、承認拒否・cancel・HTTPエラーも確認する。
401/403のメール取得拒否は保持済み結果の接続世代を失効させ、429/5xxとは区別する。
サインインの任意profile取得が401/403でもisWorkingを残さないことも確認する。

会話状態・Registry組立・plugin可用性・承認UI・設定/Keychain/browser/時計/HTTPはfixture。
本番plugin catalogの動的変化や実Google/Keychain/ASWebAuthenticationSession、
Apple LanguageModelSessionはruntime実行していない。compactは本番の取得/結果gateを
実行し、端末内AI callback/最終応答の接続は静的配線検査とBitrigビルドで確認する。
`PersonPrivacyChecks`は本番cloud出典gate、`ArtifactProvenanceChecks`と
`CalendarInterfaceChecks`は本番の資料生成/承認前後gateが、fixtureのGmail拒否を
cloud/端末内の両方で尊重することを別途検証する。
会話snapshotは一時Gmail grant IDを保存・復元しない。これらを認証済みE2Eと混同しない。

`run-mcp-agent-checks.sh`は本番の一覧取得/実行extension、MCPAgentExecutionContext、
Registry/Provider、設定保存/ON-OFF更新、利用回数制限を通す。承認待ち/SDK準備待ち/
結果待ちの63 race、一覧取得中の20変更、後続サーバー待機中の先行サーバー失効、
unknown costのcache-only取得、承認拒否、上限/実SQLite ABORT/再読込、秘匿errorを検証する。
モデル状態・既存出典許可gateの返値・承認・Keychain・MCP SDK clientはfixture。
SDK準備待ちはfixtureの待機点であり、実OAuth/DNS/TLS/HTTP/SDK動作ではない。
本番MCPClientのcallback/generation guardは静的配線チェックとBitrigビルドで別途確認する。
実SDKによる複数ページ・接続変更・timeout/cancelのruntime証明と混同しない。

同じrunnerは本番`MCPResultAuthorization`と会話ループも実行する。
取得完了後の23変更（未知/消失したgrantを含む）、24件の保持上限、別ツール待機中の
batch拒否と次のモデル応答待機中の停止を確認する。既存の63操作中raceとは別の検証である。
`PersonPrivacyChecks`は本番のcloud出典gateがMCP結果gateの拒否を尊重する配線を確認するが、
そのテストのMCP gate自体はbool fixture。snapshot codecは一時grant IDを保存・復元しない
ことを確認する。実MCP SDK/モデル送信/認証済みアカウントのruntime検証ではない。

`mcp-connection.e2e.ts`は未接続の管理画面と追加フォームのLight/Dark、空の保存不可、
料金未確認が初期値であること、未保存の取消と再起動後の未登録状態を確認する。
認証・接続確認・保存は操作せず、偽tokenや接続済み表示を作らない。

## GitHub Actions

`.github/workflows/quality.yml`はread-only権限で同じホスト検証を実行し、
失敗時もログをアップロードする。[GitHubの公式案内](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)
にある`xcode-27` ARMランナーを使用する。特定のSDK patch版を仮定せず、
実行時のSwift/iOS SDK版をログに残す。checkoutとartifact ActionはSHA固定。
過去コード比較のためGit履歴を取得する。

この設定を追加しただけではGitHub上で実行済みではない。
Bitrig CLIとビルド済み.appがないGitHubホスト上で完全なBitrigビルドや
UI E2Eを行ったとは扱わない。今回はホスト検証のみを自動化する。

## 未検証の境界

実LLM、実OAuth・実アカウント、外部送信・課金、実カレンダー/CloudKit、
実機の録音・音声セッション・電池、Officeアプリでの全ページ描画は別の検証。
静的テストは実際のVoiceOver、IME、Dynamic Type、Liquid Glassの視覚確認を代替しない。
測定fixtureの時間は端末のFPS/入力遅延/電池性能を示す数値ではない。
