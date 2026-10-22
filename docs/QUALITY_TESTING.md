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

UI E2Eは既存`e2e`スキルの手順で実行する。テスト専用Simulatorへ
再インストールするので、Bitrigのユーザープレビューや実端末では実行しない。
`tests/ui-helpers.ts`の再起動は同一シナリオ内の永続化確認に使う。
APIキーを環境から外し、モデル呼出を含まないテストを選択する。
テレメトリーも無効にする。失敗・skip・未実行は成功に合算しない。

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
