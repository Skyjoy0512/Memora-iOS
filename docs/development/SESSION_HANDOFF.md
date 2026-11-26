# セッション引き継ぎ

Bitrig の Memora iOS プロジェクトで継続する。[実行状態](EXECUTION_STATE.md)、[バックログ](TASK_BACKLOG.md)、[テスト状態](TEST_STATUS.md) と `git status --short --branch` を最初に読む。GitHub は `github`、Bitrig のバックアップは `origin`。2026-11-26 の再開時に既存差分を確認した。

## 確定済みの検証

- `0e6ad7bf` のバックアップ復元は生のファイルと SQLite を使ったホストチェックに通過。実機のデータ保護は未実施。
- `c54381d2` の長時間音声計測の実行条件と結果は [音声検証](../AUDIO_MEASUREMENT.md)。通常の音声チェックも単独で通過した。
- `abe0b9e0` の Notion と Library ランナーの修正は個別に通過。全体の一次結果は `/Volumes/DevSSD/Development/Temp/memora-release-qa.i9t3CZ/results/summary.json`、二次結果は `/Volumes/DevSSD/Development/Temp/memora-release-qa.GwMzqd/results/summary.json`。
- 二次結果には別の音声失敗がある。検証条件を変更せず、`next-generation.log` の `SegmentedAudioTranscriptionChecks` で現れる「Changed original」を調査する。

## 次に行う具体的な作業

1. Library OCR の Vision E2E は `.e2e/release-wave-photo-ocr/report.json` を確認する。合成画像を使い、Bitrigのユーザープレビューとは別の端末に限定する。
2. Releaseビルドは Bitrig ログ `2026-11-26T21-08-11-46f5a7d4.log` の末尾で終了を確認する。Debugの写真検索プレビューは `2026-11-26T21-05-32-8100eb03.log` で成功。
3. OCR-01 は正規の写真ファイルと閲覧範囲を再検証し、端末内 Ask AI の出典を原画像に結びつける。クラウド履歴再利用への伝播に対する失効テストを先に作る。
4. STORE-02 は旧原本を残した記録単位移行と中断回復を計画し、書込・復元・取り消し・トランザクションに共通の入口があるか現行コードで確定する。
