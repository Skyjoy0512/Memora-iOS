# セッション引き継ぎ

Bitrig の iOS プロジェクトで継続する。[実行状態](EXECUTION_STATE.md)、[バックログ](TASK_BACKLOG.md)、[テスト状態](TEST_STATUS.md) と `git status --short --branch` を最初に確認。GitHub は `github`、Bitrig は `origin`。

## 検証済み

- `121fca99` の写真検索は iPhone 18 Pro Max の実 Vision と SQLite で、未訪問写真の OCR と原本削除後に検索から消えることを検証。詳細は `.e2e/release-wave-photo-ocr-verified/report.json`。
- `ee4f947f` の5セクションとダーク表示は iOS E2E 2件成功。詳細は `.e2e/release-wave-workspace/report.json`。
- `d1fb8763` と `2adfc90b` でクラウド履歴の来歴条件を追加し、バックアップから再送の根拠を持ち込まないようにした。ツール統合と会話根拠のホスト検証成功。
- `393622db` の保存比較は100・1千・1万・5万件の全件方式と記録単位方式を同条件で計測。SQLite 版の本番移行は未実施。
- `ef6eb67d` の記録日付き出典はホストの FTS・文脈・引用テストと、専用 iOS E2E の記録日表示、所属変更の拒否、正常な文字起こし画面への遷移が成功。`.e2e/release-wave-project-citation-verified/report.json` の該当シナリオを参照。
- Phase 5 の長時間音声は AVFoundation、実 SQLite、合成認識結果を使ったホスト検証。計測結果は [音声計測](../AUDIO_MEASUREMENT.md)。

## 続きの作業

1. 固定版 `393622db` の品質ゲートは `/Volumes/DevSSD/Development/Temp/memora-release-qa.0HZVXF/results/summary.json` を確認。長時間 WAV の初回試験が期待した認識回数まで達せず、該当スイートは失敗した。失敗理由を付けた脚本の単独実行は成功。統合環境で再現した場合は取得した理由から原因を特定する。
2. Native Header の再検証では現行の接続状態のアクセシビリティ値、空のライブラリの録音ボタン、追加メニューからノート作成までを確認する。実機の VoiceOver と最大文字サイズの主要画面巡回は残る。
3. OCR-01 は既存 `MediaIndexEntry` の元画像の版と現在の範囲を確認し、端末内 Ask AI から元画像へ戻れる根拠を実装する。プロジェクト・個人領域間のアクセスと、OCR 由来の文脈がクラウド履歴に伝播しないことを検証する。
4. STORE-02 は増分移行を本番ストアから分離して検証する。記録の ID・順序・添付参照が一致すること、途中終了・競合で旧原本を読めることを先に確認する。
