# Memora 1.0 品質改善

開始日: 2026-10-22。現在の作業ブランチ: `main`。

## Phase 1: 選択統合と品質基盤

GitHubから取得した開始時点のHEAD:

- main: `f41fd399e8bcc7d655b08526010935f7a2f7a046`
- feat/askai-integrated-scenarios: `599ff5e05ff22b7b3395b6ae61f3e2a20f7d1568`
- 共通祖先以降: main側41コミット、対象側11コミット、対象固有18ファイル。

ブランチの一括mergeは行わず、現行mainへ必要な差分だけを前方移植する。
履歴上は対象ブランチをmerge済みにはしない。現行のナビゲーション、
モノトーン、Liquid Glass、Journalのフラットな表示は維持する。

### 対象差分の判断

| 差分 | 判断 |
| --- | --- |
| AskAIIntegrationScenarioChecks、ArtifactOperationsChecks、2つのrunner | 採用。実Office生成・再読込、SQLite保存失敗、人物別許可、出典失効、workspace変更、メール下書き、選択tool制限を再検証 |
| AIPluginExecutionPolicyの選択構築 | 採用。単独コンパイルされる既存policyにAIPlugin依存を持たせず、`+Selection` extensionへ分離 |
| PersonFixtureModelと総合runnerへの登録 | 採用。既存の独立ホストチェックを維持 |
| ProjectSourceFilesの保存先差替え | 修正採用。`MEMORA_HOST_CHECKS`コンパイル時だけ許可し、通常アプリの保存先を環境変数で変更しない |
| ProjectMetadataTransport、WebResearchClientのURLSession設定注入 | 採用。ホスト制限、HTTPS、redirect拒否、cookie/credential/cache無効化、時間・容量制限は維持 |
| ArtifactExportFileとDocumentDetailViewの共有処理 | 修正採用。共有用コピーを作り、削除は一時ディレクトリ直下の通常ファイルだけに限定。原本・ディレクトリ・symlinkを残す検証を追加 |
| compile-ios-app.sh、typecheck-ios-app.sh | 不採用。この登録済みBitrigプロジェクトでは完全なビルドを実行できる。worktreeのproducts pathに依存する代替手順を増やさない |
| 過去のSCENARIO_PHASE2/VALIDATION、backlog追記 | 過去の成功結果を今回の証拠として移植しない。今回の結果をこの文書に記録 |

### 検証の境界

Hostのモデル状態、承認入力、OSサービス、HTTP応答はfixture。
本番domain extension、LocalStore/SQLite、ProjectSourceFiles、Office生成・抽出、
registry/policy、provenanceを通す。実アカウント、OAuth、APIキー、有料APIは使用しない。
既存のCloudSessionChecksは本番CloudAgentSessionと両API形式/JSON/SSEも通す。
この検証は録音ハードウェア・実LLM・実承認UI・Officeの最終描画の証明ではない。

Project.jsonにXcodeテストターゲットはない。`bitrig test -list -json`は
その理由でテストを列挙できなかった。ホストチェック、UI E2E、Bitrigの
Debug/Releaseビルドを別の結果として報告する。

変更前のDebugビルド成功: `2026-10-22T10-03-35-ebf11798.log`、既存警告11件。
選択統合後のDebugビルド成功: `2026-10-22T10-06-03-ff0d7368.log`、既存警告11件。
新規のシナリオ・成果物操作runnerは両方成功。

既存総合チェックの再実行で、現行16スキルに対する旧15件の期待値と、
SwiftUI部分型検査のMemoraSpacing依存漏れを検出して修正。
E2EではLibrary起動・歯車のみの設定ボタン・サイドメニューに合わせ、
古いJournal起動前提と曖昧なテキストlocatorを修正する。
総合検証の最終結果は完了後に追記する。

画面記録: `docs/qa/memora-1.0/phase1/`。before/afterは同じ端末の観測。
保存した画像を目視した範囲だけを視覚確認済みとする。

## Phase 2〜7

Phase 1の最終検証後に順番に着手する。以下は未完了であり成功扱いしない。

- Phase 2: 会議→タスクの統合経路、Research出典の永続化・プロジェクト追加、構造化UI、プラグイン復旧。
- Phase 3: Journal挿入時刻・編集・保存失敗時の入力保持・外部カレンダー権限。
- Phase 4: 同じfixtureによる変更前後の実測と、安全な検索・集計最適化。
- Phase 5: ソース解析状態、重複・再試行、古い案内文の修正。
- Phase 6: 外部連携のエラー・権限変更のfixture検証。実認証やOAuth scope拡大は実施しない。
- Phase 7: 視覚・アクセシビリティ・IME・Reduce Motionの最終確認、思考ロゴの調査。
