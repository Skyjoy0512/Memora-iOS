# 現行mainの品質再レビュー — 2026-11-09

開始HEAD: `64ec4fbe`。開始時の作業ツリーはクリーン。
Gitの著者情報だけでOpenCode / DeepSeek / Codexの担当を確定できないため、
生成元ではなく現行コードの挙動を評価した。新機能・外観の変更は対象外。

## 対象と方法

- [x] 構成・履歴・既存の監査と未接続サービスの境界を確認。
- [x] SQLiteの保存、会議編集、下書き、資料の追加・編集、復元、削除を重点レビュー。
- [x] 録音開始・確定・区間再開、文字起こし結果の反映、話者解析の非同期境界を確認。
- [x] Ask AIの承認、資料引用、MCP/Gmail/Notionの実行時権限を確認し、既存fixtureを実行。
- [x] UIの現行契約と検査コードの不整合を修正。SwiftUIの状態・編集経路を確認。
- [x] 最終検査結果とシミュレータ操作の結果を下記へ記録。

Appは約1,430ファイル。全ファイル・全画面を人手で網羅した監査ではない。
手動の重点レビューと、本番コードをコンパイルする既存の横断host suite、
専用シミュレータの決定的E2Eを組み合わせた。

## 修正した問題

| 優先度 | 確認した問題 | 修正と確認方法 |
| --- | --- | --- |
| P1 | `updateMeeting`が保存結果を待たず、保存失敗時にもメモリと検索キャッシュを変更し成功を返す | 候補をSQLiteへ保存できた場合だけ公開。SQLite ABORT時のモデル・キャッシュ・再読込不変、再試行成功を検査 |
| P1 | 会議の共通更新に復元中・チーム・保護中・取消の拒否がない | 共通入口で拒否。同期更新と既存の非同期編集の両方で拒否条件を検査 |
| P1 | 読み取れない下書きを、保存済み本文や空文字で置き換えて編集できる | 複数フィールドの`DraftStore.readAll`で全件確認後に編集を許可。共通編集、ノート、要点、メール、字幕、スライド、Ask AI起動時へ適用。保存・削除も不正な元バイトを保護 |
| P1 | 遅い編集保存が、後から入力した下書きを削除し得る | 直列保存キュー内で内容一致を確認して削除。ブロック編集には編集世代も確認。遅い本文更新で新しい作業中本文を消さない。実キューで新しい保存→古い完了の順を検査 |
| P1 | ノート編集が編集開始時の資料を検査せず、他の画面の編集を上書きし得る。下書き削除も別取引 | 開始時の資料と`LocalImportContext`を検査し、本文保存と下書き削除を同じSQLite取引にする。削除失敗で両方ロールバック、古い資料の拒否を検査 |
| P1 | 公開範囲変更・話者解析が同じ全会議スナップショットを二重保存する | 共通更新の確定だけを使う。話者解析にはワークスペース世代・公開範囲の再検査も追加。話者解析の実機動作は未検証 |
| P1 | 写真の保存後に会議更新が失敗すると、未登録ファイルが残り得る | 保存先を作成前に確認し、登録失敗時は既存の媒体削除経路で片付ける。実写真取込の全障害試験を完了したという意味ではない |
| P2 | 文字起こし開始・結果の保存失敗でも後続処理へ進む | 更新失敗時は後続を開始しない。進捗だけの変化は永続化しない |
| P2 | 横断検査のソース一覧が現在の引用・録音manifest依存を含まず停止する | 3つの引用runnerとサンプル検査へ実依存を追加。スキップ・モック置換で回避しない |
| P2 | UI検査が旧作成Menu、旧間隔・旧ジャーナル入口を要求する | AGENTS.mdと現行UIに合わせた契約へ更新。要素の存在、順序、fileImporter常設、下書きの原子的保存を維持 |

## 検証結果

| 検査 | 結果 | 証拠・範囲 |
| --- | --- | --- |
| `bitrig preview -platform iOS` | PASS | Simulator向けアプリと拡張をビルドし、Bitrigプレビュー起動を確認。既存の非推奨APIなど11 warning |
| next-generation | PASS | 引用runner修正後の全実行。資料取込、要約、FTS、MCP/Gmail/Notion、承認、文書、バックアップ、カレンダーのfixture。会社資料65レイアウトのhost検査を含む |
| design-refresh | PASS | 古いUI契約とサンプル検査の依存修正後の全実行。読み込み・motion・会話・予算などを含む |
| background-summary / summary-reliability / composer-layout / optimization | 4系統PASS | 現行修正を含む横断実行。保存キュー・下書きの追加回帰もoptimizationから実行 |
| 会議編集 / 資料ノート保存 | PASS | 実SQLiteのABORT、同期/非同期編集、取消、並行更新、下書き削除の失敗、古いノートの保存拒否 |
| recording-media / microphone-input / chunk-writer | PASS | 実ファイル・SQLite、所有権とrollback、44.1/48kHz変換、区間境界とrotation。実マイク収録は含まない |
| inline-citation | PASS | ページ/時刻の境界、変更済み資料引用の失効 |
| marketplace | PASS | 実Swiftカタログ87定義とサーバー側codec、7 API fixture検査。Firebase未配備 |
| audio ledger | PASS | 実SQLiteの11検査、`ledger.mjs`構文。D1/HTTP/購入/本番課金は含まない |
| runner自身の検査 / `git diff --check` | PASS | 4 + 4件。途中失敗を成功へ変換しないことを検査 |
| Bitrig Simulator操作 | PASS | Libraryの起動と、共有作成シートの表示・操作順序・閉じるを確認。データ変更なし |

hostログの保存先は`/Volumes/WorkspaceSSD/Development/Agents/MemoraSupervisor/`。
`review-host-final-summary-20261109.json`は実際に成功した6系統の各ログを参照する。
途中の失敗ログ（`memora-quality-o2repuyt` / `memora-quality-mdxpowku`）も残した。
音声途中再開は単独検査と最終next-generation全実行で成功したが、途中の一過性失敗の原因は未確定。

シミュレータE2Eは対象5シナリオの最終結果がPASS。

| シナリオ | 結果 | 実行記録 |
| --- | --- | --- |
| 読めない要約下書きの編集拒否・元バイト保持 | PASS / 61秒 | `.e2e/review-20261109/report.json` |
| 段落・リスト・表の編集と原文保持 | PASS / 83秒 | 同上 |
| 日本語置換・Unicode・画面移動・再起動後の本文保持 | PASS / 102秒 | `.e2e/review-japanese-20261109/report.json` |
| ノート作成/編集のSQLite失敗・下書き復元・再試行・再起動後の本文保持 | PASS / 136秒 | `.e2e/review-note-recovery-20261109/report.json` |
| Ask AIの下書きが読めない起動時の保存保護 | PASS / 48秒 | `.e2e/review-composer-20261109/report.json` |

初回E2Eは2/4 PASS、2件停止。1件は戻るボタンの旧ラベルを参照し、もう1件は
表示済みの行を下へドラッグしてズーム画面を閉じる古い検査手順だった。
現行の戻る識別子と、表示済みの要素を不要にドラッグしない手順へ修正して、
それぞれ独立に再実行してPASS。初回reportも残し、失敗を削除・skipしていない。

この検査は専用iPhone 18 Pro Maxの新規データを使い、プレビューのデータベースには書き込まない。
CLIにモデル名が表示されても、`agent.*`を使わない決定的操作であり、全実行でモデルtoken 0。

再実行の入口:

```sh
bash tools/checks/run-quality-checks.sh
bash tools/checks/run-recording-microphone-input-checks.sh
bash tools/checks/run-recording-chunk-writer-checks.sh
python3 -B tools/checks/run-recording-media-checks.py
bash tools/checks/run-inline-citation-checks.sh
bash tools/checks/run-marketplace-checks.sh
python3 -B backend/audio-intelligence/test_ledger.py
npx e2e run tests/draft-protection.e2e.ts tests/markdown-replacement.e2e.ts tests/project-source-recovery.e2e.ts --workers 1 --retries 0 --no-cache
bitrig preview -platform iOS
```

## 残る境界

- 実機の着信/Bluetooth/ロック/長時間録音、実音声のSTT精度、VoiceOver/実IMEは未検証。
- クラウドLLM、外部アカウント、実課金、Firebase/CloudKit本番、StoreKitは接続・配備していない。
- 全会議の単一blob保存は維持。今回の同期更新は保存成功の整合性を優先し、
  大量データでのメインスレッド待ち時間を解決したとはしない。進捗更新は保存対象から外した。
- 読めない下書きは保全して編集を止める。破損した下書きの復旧・明示破棄専用UIは追加していない。
- 音声途中再開のhost検査が横断実行中に一度失敗（`Multipart resume failed`）。
  同じ本番コードの単独再実行は成功した。根本原因は未特定で、自動リトライや判定緩和は追加していない。
- 既存の未接続機能は[AGENTS.md](../AGENTS.md)と[実装計画](OPENCODE_IMPLEMENTATION.md)の境界を維持する。
