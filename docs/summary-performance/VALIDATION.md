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

## 容量計画・共通能力・並列

- `run-summary-planning-checks.sh`: shared catalog / user override / custom endpointのunknown、温度・低電力制約、指示/出力予約、UTF-8/emoji/改行のlossless分割、512区間上限、scheduler 1/2/3/4 workerと429 fail-stop成功。
- `run-summary-reading-checks.sh`: shared ModelCapabilitiesを使う実MeetingSummarizerで、未知モデルの短文・1,000発言の全文一括・巨大4区間の統合・短縮根拠・同時処理/中断を含め成功。
- `run-cloud-session-checks.sh`: actual summary / CloudAgentSession / URLSession with fail-closed URLProtocol成功。9 provider × model × processing mode × official/custom route、SSE/JSON、EOF・切断・拒否・HTTP失敗・継続上限・失効を確認。Opus 5 / Fable 5.1の別モデルfallback禁止とcustom Anthropic URL維持を追加確認。
- `run-motion-loading-checks.sh`: 公式資料で更新したshared capability期待値、既存のtoken/agent予算、承認、project会話/cancel/保存失敗の回帰成功。

途中の検証用fixtureにあった「未知容量でも一括になるはず」という仮定を修正し、一括テストにはレビュー済みモデル容量を明示した。未知モデルの短文経路も別に確認した。失敗ログは外部作業ディレクトリに保持。

上記単位の最終iOS preview: `2026-11-14T22-24-37-56c97a02.log` 成功（既存11警告）。性能目標の実測や実機検証とは区別する。


## 要約ジョブ内の通信session再利用

- `CloudHTTPTransportChecks`: production CloudAIService / CloudTurnStreaming / URLSessionをoffline URLProtocolで実行し、継続/次区間のsessionReuse [0,1,1]、cookie/credential/endpoint/close分離、拒否で追加request0を確認。
- `run-cloud-session-checks.sh`: 両API、selected model、EOF/HTTP/continuation/cancel/許可・予算・SQLiteの既存回帰成功。
- `run-summary-reading-checks.sh`: 実MeetingSummarizerの4part+finalが同じtransportを使うこと、既存source/ordered merge/キャンセル・編集等の回帰成功。
- iOS preview `2026-11-14T22-45-48-045e9839.log` 成功（既存11警告）。実ネットワーク・TLS・実機時間の改善は未計測。

最新の実装範囲・最終無料10群・シミュレーターUI3件と未検証事項は[2026-11-15統合検証](VALIDATION_2026_11_15.md)を参照。
