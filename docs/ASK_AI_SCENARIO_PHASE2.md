# Ask AI 統合シナリオ A〜E と成果物操作

2026-10-18。開始main `df9fa1f`。隔離worktree
`/Volumes/WorkspaceSSD/Development/Temp/memora-askai-integrated-20261018`、
ブランチ `feat/askai-integrated-scenarios`。mainは切り替えていない。

## Phase 1 — 監査と補完

既存のhost検証は、通信形式・人物許可・下書き保存・Researchループ・Office書式を
個別に本番コードへ通していた。今回、以下の不足を一続きのシナリオとして補った。

| シナリオ | 以前の到達点 | 今回追加した到達点 |
| --- | --- | --- |
| A 人物→会社提案書 | 明示personID、個別許可、`draft_email`/資料保存、SQLite再読込（`CloudSessionChecks`、`ArtifactProvenanceChecks`） | 会社テンプレート選択 → `prepareDocumentArtifact` → 実DOCX/PPTX生成 → Office再読込 → SQLite保存。別workspaceのテンプレート拒否 |
| B 過去会話→未完了事項 | FTS5/BM25検索、状態・scope・削除（`MemoryRetrievalChecks`）、応答待ちの失効（`CloudSessionChecks`） | `AIConversationProvenance.allowsReuse` と現在のタスク指紋・削除・workspace変更を同じ検査に接続。曖昧な質問は過去を断定しない |
| C Research→会社PPTX | 有限ループ、重複排除、引用範囲（`ResearchLoopChecks`）、テンプレート差込（`DocumentArtifactChecks`） | 本番`WebResearchClient`/`ProjectMetadataTransport`をscripted HTTPで通し、URL正規化・重複排除・HTML除去・抜粋/抽出本文の区別を確認。その後、反復検索 → 引用検証 → 会社PPTXテンプレート → 実ファイル → 再読込 → SQLite保存。中断時は未完了のまま |
| D 会議→メール下書き | 人物起点の下書き、承認後再検証、SQLite再読込（`CloudSessionChecks`、`ArtifactProvenanceChecks`） | 本番`read_person`で会議の決定と担当タスクを取得（同名の別人は含めない）。会議・参加者・タスクの型付き出典、不明宛先の拒否、承認後の保存、編集→再読込、`status == .draft`の維持、承認待ちの変更で保存しない |
| E @選択→許可Toolのみ | 本番registry/policyのscope・schema・無効化（`PluginDispatchChecks`）、候補/チップUI（`ComposerMentionChecks`） | 選択toolだけを実行し、未選択MCPを実行しない。選択解除・MCP無効化・テンプレートID不一致を拒否。Gmail境界はfixture transportで呼出回数を検査 |

### 本番コードとfixtureの境界

本番コード:

- `ResearchLoop`、`ResearchPlan`、`WebResearchSource`/`Report`
- `AIPluginExecutionPolicy`、`AIToolRegistry`、`AIToolDefinition`、`IntegrationProvider`
- `MemoryRetrievalOrchestrator`、`AIConversationProvenance`、`AIRecordFingerprint`
- `MemoraModel+DocumentArtifacts`、`MemoraModel+Documents`、`MemoraModel+MailDrafts`、
  `MemoraModel+MailDraftTool`、`MemoraModel+ArtifactProvenance`
- `WebResearchClient`、`ProjectMetadataTransport`（HTTP応答はfixture）
- `CompanyTemplateEngine`、`DOCXWriter`、`PPTXWriter`、`OfficeArchiveReader`、
  `OfficeDocumentExtraction`
- `LocalStore`/SQLite、`ProjectSourceFiles`（保存先だけ一時ディレクトリへ差し替え）

fixture:

- モデル応答、承認UIの入力、Gmail/MCPの接続状態とtransport
- `MemoraModel` のstored state、通知・メディア等のUI依存
- 架空の人物・会議・タスク・記録
- `ProjectSourceFiles` の保存先は環境変数
  `MEMORA_WORKSPACE_FILES_DIRECTORY` で一時ディレクトリに限定（通常起動では未設定）

外部HTTP・OAuth・実アカウント・有料APIは使用していない。CのHTTP境界は
`URLProtocol` で応答だけを差し替え、本番のリクエスト生成・ヘッダー・
`WebResearchClient.decode`・`ProjectMetadataTransport` を通した。
通常の `URLSessionConfiguration` は従来どおりephemeralで、テスト時だけ注入する。

## Phase 2 — 成果物の操作と復元

`ArtifactOperationsChecks` を追加した。

- 実DOCX/PPTXを生成し、`ProjectSourceFiles` の実ファイルとして保存。
- 資料モデルをSQLiteへ保存し、別接続で再読込。
- タイトル/本文の編集 → 保存 → 再読込。古い生成ファイル参照を失効させ、
  非同期の一時ファイル片付けを待って削除を確認。
- メール下書きの保存・編集・再読込。`status == .draft`、宛先空欄を維持。
- SQLiteの `BEFORE INSERT` triggerで資料/下書き保存を実際にABORT。
  戻り値は失敗、modelは変更前のままで、呼び出し側が保存成功として扱える値にならないことを確認（画面の成功表示自体は未検証）。
- `ArtifactExportFile` を追加し、共有用の一時コピーと後片付けを本番画面から分離。
  元ファイルを残したままコピーを作成し、シート終了後にコピーだけを削除する。
  存在しない元ファイルは書き出さない。表示名のパス区切りは除去し、
  別ディレクトリへ書き出さない。
- 出典行は削除済み・非公開化・別workspace・復元中・保護中で開けないことを確認。
- バックアップ/復元は既存 `BackupRestoreChecks`（実package + 実SQLite）を再利用し、
  重複実装しない。会話snapshotからの書き込み権限・送信許可の非復元は
  既存 `AIConversationSnapshotChecks` で確認済み。

共有シートを開けたこと、共有先アプリで開けたこと、Office全ページの描画は
今回のhost検証に含まれない。

## 実行結果

- `bash tools/checks/run-ask-ai-scenario-checks.sh`: 成功。
- `bash tools/checks/run-artifact-operation-checks.sh`: 成功。
- `bash tools/checks/run-next-generation-checks.sh`: 全スイート成功（新規2つを含む）。
- `bash tools/checks/run-motion-loading-checks.sh`: 成功。
- `python3 tools/checks/run-optimization-checks.py`: 全12テスト成功。
- `xcrun swiftc -typecheck`（iOS 27.1 SDK / iOS 26ターゲット、App/Shared全ソース）: Debug・Release構成とも
  エラー0、既存の非推奨警告20件。`tools/checks/typecheck-ios-app.sh` で再実行できる。
- `xcrun swiftc -c -whole-module-optimization`（App/Sharedを1モジュールとしてオブジェクト生成）:
  Debug・Release構成とも成功。`tools/checks/compile-ios-app.sh` で再実行できる。
  リンク、Info.plist、リソース、署名、アプリ起動は含まない。
- `swiftc -parse App/DocumentDetailView.swift App/ArtifactExportFile.swift App/ProjectSourceFiles.swift`: 成功。

ビルド制約: Bitrigは登録済みプロジェクト直下のパスだけを認識し、SSD上のlinked
worktreeでは `isn't inside a Bitrig project` で拒否した。mainを切り替えず、
他worktreeへ変更を混ぜない条件を守るため、このworktreeでは
`bitrig preview` / Releaseビルドを実行していない。代わりにiOS SDKに対する
全ソースの型検査をDebug/Release構成で行い、エラー0を確認した。ただしこれは
コンパイル・リンク・リソース処理・アプリ起動を伴うBitrigビルドではない。
シミュレータUIとe2eは未実行であり、成功とは扱わない。

## 未検証・残件

P0:

- Bitrigでこのブランチを開くか、mainへ統合した後にDebug/Releaseビルドと
  シミュレータUI/e2eを実行する。
- 実共有先アプリでのDOCX/PPTX表示、Office全ページのレイアウト・改ページ・
  フォント代替。
- 実機VoiceOver、日本語IME、録音競合、長い会話・大量データの性能。

P1:

- 実composerの@選択から本番 `pluginCatalog`/接続状態/費用承認/対象範囲を通すE2E。
  今回Eは選択済みIDのregistry/policyとfixture transportまで。
- Gmail Drafts/送信、MCP OAuth、TeamBackend、Memoria Intelligenceの実接続。
- 人物サマリーや過去episodeの意味的一致、複雑な会社テンプレート。

P2:

- 日本語Embedding/Hybrid検索、モデル課金上限、外部worker。
- 共有先ごとのファイル互換性の自動検査。

## 変更ファイル

- `App/ArtifactExportFile.swift`（共有用一時コピーと片付け）
- `App/DocumentDetailView.swift`（上記を共有経路で使用）
- `App/ProjectSourceFiles.swift`（検証時だけ保存先を差し替える環境変数）
- `App/ProjectMetadataTransport.swift` / `App/WebResearchClient.swift`（URLSession設定の注入点）
- `tools/checks/AskAIIntegrationScenarioChecks.swift`
- `tools/checks/ArtifactOperationsChecks.swift`
- `tools/checks/PersonFixtureModel.swift`（架空の会社テンプレート/実ファイル境界）
- `tools/checks/run-ask-ai-scenario-checks.sh`
- `tools/checks/run-artifact-operation-checks.sh`
- `tools/checks/run-next-generation-checks.sh`
- `tools/checks/typecheck-ios-app.sh`
- `docs/ASK_AI_SCENARIO_PHASE2.md`
- `docs/ASK_AI_SCENARIO_VALIDATION.json`
