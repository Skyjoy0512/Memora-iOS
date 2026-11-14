# 検証の実行記録

## 評価基盤（62d0f166）

- J-MeetEvalコード25365d48 / dataset6d3fc778のbyte照合・SHA256、197件・16カテゴリ成功。
- 独自評価器7単体テスト成功（rule評価・未評価Judge・重大誤り・不明計測・同条件・25goldシナリオ）。
- socket通信を遮断した上流の107テスト成功。
- iOS preview: `2026-11-14T21-49-25-d0df184e.log` 成功、既存警告11件。

## 短縮IDと診断

- `run-summary-reading-checks.sh` 成功。実MeetingSummarizerで短縮ID→元UUIDの構造化出典、既存4区間の到着順逆転→時間順統合、キャンセル・途中失敗・権限失効、編集/SQLite失敗・再開、レイアウト、資料解釈の既存検証を通過。
- `SummarySourceIndexChecks`: 1,000発言の原文全体・空白/改行・話者・開始/終了・ID往復、重複UUID、未知参照、cache使用量、不明値、1チャンク時刻、metrics JSON成功。
- 最終レビューで「短縮表現を送信しなかったのにS番号の根拠を受理する」可能性を除去。保存用検証はUUIDに戻せた参照だけを受理。focused source-index再検証成功。
- `run-deepseek-summary-checks.sh` 成功（2,178,128 bytesの合成SSE、9,000 reasoningイベント、本文終端維持、実APIではない）。
- `run-summary-scheduler-checks.py` 成功（OS lease/cancelのモック）。
- 最終iOS preview: `2026-11-14T22-00-14-9227bbc5.log` 成功、既存警告11件。

外部作業ログ: `/Volumes/WorkspaceSSD/Development/Agents/MemoraSummaryPerformanceValidation`。
実モデル、実アカウント、実機の録音・電池・発熱・CPU性能は未検証。今回の単位はUIを変更していない。以前のUI E2Eを今回実行したとは扱わない。全9群の再実行は統合段階で実施する。
