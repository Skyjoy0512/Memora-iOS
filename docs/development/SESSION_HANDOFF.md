# セッション引き継ぎ

Bitrig の iOS プロジェクトで継続する。[実行状態](EXECUTION_STATE.md)、[バックログ](TASK_BACKLOG.md)、[テスト状態](TEST_STATUS.md) と `git status --short --branch` を最初に確認。GitHub は `github`、Bitrig は `origin`。

## 検証済み

- `121fca99` の写真検索は iPhone 18 Pro Max の実 Vision と SQLite で、未訪問写真の OCR と原本削除後に検索から消えることを検証。詳細は `.e2e/release-wave-photo-ocr-verified/report.json`。
- `ee4f947f` の5セクションとダーク表示は iOS E2E 2件成功。詳細は `.e2e/release-wave-workspace/report.json`。
- `d1fb8763` と `2adfc90b` でクラウド履歴の来歴条件を追加し、バックアップから再送の根拠を持ち込まないようにした。ツール統合と会話根拠のホスト検証成功。
- `393622db` の保存比較は100・1千・1万・5万件の全件方式と記録単位方式を同条件で計測。SQLite 版の本番移行は未実施。
- `ef6eb67d` の記録日付き出典はホストの FTS・文脈・引用テストと、専用 iOS E2E の記録日表示、所属変更の拒否、正常な文字起こし画面への遷移が成功。`.e2e/release-wave-project-citation-verified/report.json` の該当シナリオを参照。
- `a794baac` の統合ホスト検証は11/11成功。結果は `/Volumes/DevSSD/Development/Temp/memora-release-qa.KSpBuS/results/summary.json`。同版のレイアウト・原画像 E2E は8件成功し、`.e2e/release-wave-ocr-and-layout/report.json` にある。
- `6d4fe17c` の会話の継承・クラウド再利用・復元は専用ホストチェックが成功した。
- `54974876` の記録詳細の写真出典は本番の文脈生成と模擬 Vision を使うホスト検証および元画像・削除後の質問履歴 E2E が成功。`.e2e/release-wave-record-photo-accessibility/report.json` の写真シナリオを参照。同じ実行の最大文字サイズ・候補メニューの失敗は別途検証中。
- `27956d28` は5万件までの移行リハーサル、`f42bb302` は会議 Bot の参加先・同意・状態遷移の専用ホスト検証。どちらも実ユーザーの移行・実会議は未実施。
- `ab4c39b1` の最大文字サイズ・候補の枠・元画像 E2E は `.e2e/release-wave-record-photo-layout-verified/report.json` の4件成功。 `2dc48020` の端末内グローバル写真検索は専用ホストと Bitrig Debug 成功。
- Phase 5 の長時間音声は AVFoundation、実 SQLite、合成認識結果を使ったホスト検証。計測結果は [音声計測](../AUDIO_MEASUREMENT.md)。

## 続きの作業

1. 明示した記録日での範囲限定は `App/ProjectContextBuilder.swift` と `App/ProjectSearchIndex.swift`。期限と複数日の比較を誤って除外しないことをホストで確かめ、Bitrig ビルド結果を確認する。
2. `54974876` の統合結果は `/Volumes/DevSSD/Development/Temp/memora-release-qa.doiX1E/results/summary.json` で11/11成功。 `2dc48020` は `/Volumes/DevSSD/Development/Temp/memora-release-qa.3dU0fS/results/summary.json` で実行中。実機の VoiceOver、長時間音声、モデルは未検証。
3. グローバル Ask AI の原画像参照は読取済み写真を対象とし、写真を含む旧回答はそのまま再投入しない。実機の Apple Intelligence で回答と引用を検証し、資料生成で同じ根拠の参照を実装する。
4. STORE-02 は移行リハーサル通過後の作業として、ページ単位読込と各入口の書込順序を合成環境で検証する。音声を含む実利用データで切替を行う前に、復元とロールバックの受け入れ条件を満たす。
