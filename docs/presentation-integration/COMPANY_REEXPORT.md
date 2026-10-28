# 編集した会社PPTXの確認付き再出力・ファイル履歴

2026-10-28。開始main: `c751a8ae58b15d1c13d446e009ee40c6fc7d152e`。
実装コミット: `31c8df1`。前フェーズの[条件限定append exporter](COMPANY_APPEND.md)を、
保存済み資料の詳細画面へ接続した。指示書全体の完了報告ではない。全完成条件は **0 / 65** のまま。

## 実装完了

- 構造化スライドの会社資料に「会社PPTXを書き出す」を追加。編集を保存して詳細へ戻り、書式名・現在の版番号・別ファイル生成・前回成果物の保管・外部送信なしを確認して開始する。
- 元の会社テンプレートから新規スライドを生成する。直前の成果物へ再追加してページを累積させない。会社の原本・以前の成果物を書き換えず、成功後だけ最新の参照を切り替える。
- `DocumentArtifactRevision`へ旧ファイル名、PPTX/DOCX形式、本文版、関連テンプレートID/版、保管日時を保存。保管日時は元の出力日時を推測した値ではない。旧文書のoptional decode互換を維持する。
- 以前のファイルの開示、Quick Lookへの確認、保存・共有を追加。操作時に、現在の資料に含まれる参照・ファイル名・通常ファイル/非symlinkを再検査する。
- ファイル生成とSQLite確定を分離。確定直前に文書全体・テンプレート全体・workspace世代・保存可否・復元・取消を再確認。同期的なDB保存が成功してからモデルを更新する。途中の別資料の変更も保持する。
- 失効/取消/保存失敗時は未公開の新ファイルを片付ける。他の資料・履歴・テンプレート・プロジェクトソースが参照しているファイルは削除しない。
- バックアップに最新/過去の全ファイルを含め、復元時もメタデータとバイトを保持する。資料削除の確認文に履歴削除を明示し、会社原本や他用途の参照は残す。
- 最大100履歴。上限時は再出力を拒否し、自動削除しない。既存の500MBソース保存上限も維持する。履歴の個別削除/本文を過去版へ戻す機能は今回追加していない。

UIはnative-app-designの方針を使い、既存詳細画面へフラットなボタンとDisclosureGroupを追加した。
確認はApple標準のconfirmationDialog、処理中は短いshimmerと取消、失敗は理由のあるalert。
装飾カード・ロゴ・ゲージ・経過秒は追加しない。操作は44pt以上、拡大文字でも到達可能な構成。
[Appleのalerts](https://developer.apple.com/design/human-interface-guidelines/alerts)・
[file management](https://developer.apple.com/design/human-interface-guidelines/file-management)を参照した。
ナビゲーション、録音、標準PPTX/PDF共有、企業マーカー差し込み経路は変更していない。

## 検証完了と境界

| 検査 | 実行結果 | 境界 |
| --- | --- | --- |
| 再出力ライフサイクル | 実Swift PPTX生成、本文編集、旧バイト保持、2ページ出力、会社版3→4、実SQLite再読込 | 合成会社原本とb01。UIの確認操作そのものではない |
| 生成を中断した11条件 | 編集、削除、workspace往復、世代変更、会社版/計測変更、保護、復元、取消、SQLite ABORT、新ファイルの他用途参照 | 本番prepare/commit/discardをテスト用gateで中断。実OSプロセス終了ではない |
| 不正入力/互換 | 旧codec、履歴重複、path/形式/版番号、100件上限、元成果物/原本欠落、異なるテンプレートIDを拒否 | あらゆる企業資料を受理できるとはしない |
| backup/restore | 実packageと実SQLiteで履歴・バイト復元、旧backup、欠落/不正参照/rollback | 隔離fixture。ユーザーの実データを操作していない |
| 標準65型 | 65/65で固有geometry、編集可能PPTX、PDF文字、日本語/出典、codec/編集/empty/独立XML検査 | 短い固定fixture。Office/実機の最終認定ではない |
| 会社65型の回帰 | next-generation内の65/65 append検査を再実行 | 条件限定書式。新UIで全65型を保存した検査ではない |
| 部分修正の権限回帰 | `--presentation-revision` Pass | 実provider呼出しなし |
| 既存6スイート | 全Pass | ローカルホスト。CI本体とは区別する |
| Debug preview / Release | 両方成功。既存11 warnings | iOS Simulator向け。実機ビルド/実行ではない |
| OSSリソース | 22/22、MIT著作権/本文維持 | 依存の追加なし |
| Simulator表示 | iPhone 18 Pro Max、Light/Dark、最大Dynamic Type、Reduce Motion、確認/取消/履歴/未対応/完了例 | 保存しないDEBUG表示例。本番資料のUI→生成→保存E2Eではない |

既存6スイート: next-generation / design-refresh / background-summary / summary-reliability /
composer-layout / optimization。新しい再出力チェックをnext-generationへ追加し、従来検査を削除/skipしていない。
最初の専用チェックではfixtureからprivateなstore URLを参照していたため、fixture自身でURLを保持するよう修正した。
最終コードで専用チェックと6スイートを再実行している。

### 検査ログ

- [再出力と11条件](company-reexport/checks/reexport-final.log)、[backup/restore](company-reexport/checks/backup.log)
- [65型](company-reexport/checks/presentation-final.log)、[部分修正の権限](company-reexport/checks/revision-access-final.log)
- [6スイート結果](company-reexport/checks/summary.json)と同フォルダの個別ログ
- [Debug preview](company-reexport/checks/preview-final.log)、[Release](company-reexport/checks/release-final.log)、[OSS](company-reexport/checks/oss-final.log)

GitHub Actionsは同じHEADの[Host quality checks](https://github.com/Skyjoy0512/Memora-iOS/actions/workflows/quality.yml)で照合する。
Project.jsonやtest targetは変更していない。

### 実Simulator画像

以下は本番と同じ操作/確認/履歴コンポーネントを使う**架空の表示検証画面**。
実ファイルを作成/共有した証拠として扱わない。元データは置換していない。
追加UIのため、同内容の変更前画像はない。全画面のBefore/Afterもこのフェーズでは実施していない。

| 状態 | 画像 |
| --- | --- |
| 開始/確認 | [開始](company-reexport/screenshots/ready-light.png) / [確認](company-reexport/screenshots/confirmation-light.png) |
| 履歴 | [Light](company-reexport/screenshots/history-light.png) / [Dark](company-reexport/screenshots/history-dark.png) |
| 処理/取消 | [Light](company-reexport/screenshots/working-light.png) / [Reduce Motion・Dark](company-reexport/screenshots/working-reduce-motion-dark.png) |
| 完了/未対応 | [完了例](company-reexport/screenshots/finished-dark.png) / [未対応例](company-reexport/screenshots/blocked-dark.png) |
| 最大Dynamic Type | [上部](company-reexport/screenshots/accessibility-top-dark.png) / [履歴と操作](company-reexport/screenshots/accessibility-history-dark.png) |

AX上で確認/履歴の操作名を確認。VoiceOverの実聴取、実機、小型端末、回転、低メモリ、キーボード/IMEの全操作は未検証。
検証後、Simulatorの外観/文字サイズ/Reduce MotionをLight/large/disabledへ戻した。

## 変更前との比較

| 項目 | 開始HEAD | 今回 |
| --- | --- | --- |
| 編集後の会社append再出力 | 内部exportのみ、詳細UIは未接続 | 詳細から明示確認付きで接続 |
| 以前の成果物 | 最新への参照のみ | 上限付き履歴、確認/共有、backupへ同梱 |
| 競合時の公開 | 内部のworkspace/書式検査 | 正確な保存済み本文と確認snapshotを確定直前にも検査 |
| 原本/マスター | 条件限定append、原本保持 | 同じexporterを再利用。対応範囲を広げたとはしない |
| 会社PDF/ネイティブ描画 | 未実装 | 未実装 |
| 65型の全条件完成 | 0/65 | 0/65 |

## 未実装・既知の制限・次の課題

- 任意企業書式/プレースホルダー、会社書式PDFとネイティブpreview一致は未実装。960×540pt等の[対応条件](COMPANY_APPEND.md)は変わらない。互換性がない場合は理由を表示して拒否する。
- scalarマーカー方式や旧箇条書きだけの文書は対象外。既存の企業テンプレート生成経路を維持し、構造化appendへ無言で変換しない。
- 同じUIの実資料保存E2E、実LLMの65型選択、Office/Keynote編集と最終描画、実機の全65型確認は未検証。Quick LookやXML検査で代用しない。
- XCTest/XCUITest/SnapshotTesting target追加は今回行っていない。DEBUG表示例をSnapshotTesting自動回帰と呼ばない。
- CPU/メモリ/電池/録音/SQLite/LLM/画面性能のBefore/Afterは未計測。保存は既存の全documents JSON batchで、高速化したとは主張しない。
- 生成中にOSからプロセスが終了した場合の未参照ファイル自動回収は未実装。通常の失敗/取消は片付けるが、プロセス終了耐性の完成とはしない。
- 新しいOSS、クラウドサービス、契約、外部送信、有料API、固定費は追加していない。OSS表示は既存の設定最下部に集約したまま。

## 再現コマンド

```sh
TMPDIR=<外部SSDの作業先> bash tools/checks/run-artifact-operation-checks.sh --company-reexport
bash tools/checks/run-backup-restore-checks.sh
bash tools/checks/run-artifact-operation-checks.sh --presentation-revision
MEMORA_CHECK_ROOT=<作成済みの外部SSD検査先> bash tools/checks/run-presentation-checks.sh
bash tools/checks/run-quality-checks.sh --output-dir <未作成の結果先>
python3 -B tools/checks/verify-oss-resources.py
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
```

表示例: 設定 → 診断とプレビュー → 状態と復旧UI → 65レイアウトの表示と編集 → 会社PPTXの再出力。
新しい表示例はDEBUGだけ。本番操作は関連会社テンプレートを持つ保存済みスライド資料の詳細に置く。
