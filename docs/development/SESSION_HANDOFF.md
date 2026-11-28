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
- `ab50fad1` で最大文字サイズの E2E は幅402pt の iPhone 18 Pro でも3件成功（`.e2e/dbg-narrow-polish8`、`.e2e/dbg-narrow-design`）。同じ3件は iPhone 18 Pro Max でも成功（`.e2e/dbg-wide-accessibility`）。浮遊する AI 操作の上や固定見出しの下を掴まないこと、ズーム遷移を戻さないことが条件。
- `e2f20004` の SealedReader は5万件の合成ストアで、ページ順・改変・欠落・競合・取消・封緘失敗を検出。先頭ページ0.78 ms、末尾0.70 ms（ホスト、温キャッシュ5回中央値）。本番の保存経路は全件 BLOB のまま。
- `f43cd2b6` の記録日指定と `31becc94` の MCP 認証中断は専用ホスト検証が成功。`63626753` はリリース根拠の記録。
- Phase 5 の長時間音声は AVFoundation、実 SQLite、合成認識結果を使ったホスト検証。計測結果は [音声計測](../AUDIO_MEASUREMENT.md)。

- 記録単位の保存は iPhone 18 Pro Max の実コンテナで確認: サンプル8件を追加し、再起動後も開けた。`documents` の `memora.meeting.<id>` 9件と manifest が実データとして存在する。
- `collection-polish` 4件と `screen-review-samples` 1件は現行ビルドで成功。後者は浮遊する入力欄の下を押していたテスト側の問題で、行を安全な範囲へスクロールしてから押すよう直した。

## 続きの作業

1. QA-02 は判断の編集を「その他 › 要点・決定事項を編集」で再検証済み。ポスター3件は `FeatureFlags.isInlineSummaryPosterEnabled = false` のため skip。QA-03 の `screen-polish`／`experience-polish` は17件すべて成功し、タスク画面のタイトル重なりも `ff8d918d` で修正した。
2. STORE-02 は本番経路を記録単位へ接続した（`ef766f66`）。次は (a) 実データ（転写・写真入り）の移行と復元・ロールバックの受け入れ、(b) `performance-contracts` を含む12スイートの統合実行、(c) STORE-03（起動時に本文を読まない段階読み込み）の設計。行の読込は BLOB より 12〜37% 遅いので、冷起動の目標には STORE-03 が要る。
3. 音声は信号演算を Accelerate 化し、VAD を `.cpuOnly` にした（`f1d1f26b`）。実機の電池・熱、連続録音時の VAD、日本語 CER の実測が残る。
3. グローバル Ask AI の原画像参照は読取済み写真を対象とし、写真を含む旧回答はそのまま再投入しない。実機の Apple Intelligence で回答と引用を検証し、資料生成で同じ根拠の参照を実装する。
4. 統合品質ゲートは `run-quality-checks.py --output-dir` で11スイート。`2dc48020` と `c489bcfb` は11/11成功。`c489bcfb` の結果は `/Volumes/DevSSD/Development/Temp/memora-release-qa.JE0mxQ/run/summary.json`。
