# 要約改善の現況と残タスク

2026-11-15更新。過去の途中記録より本書とリンク先の追加単位を優先する。過去の失敗ログや未検証結果を、後日の成功で書き換えない。

## 実装の現況

| 領域 | 現況 |
|---|---|
| 適応型要約 | 固定見出し/空欄補完の廃止、55プロファイルの互換性、編集/履歴/タスク/根拠の既存基盤を維持 |
| モデル共通処理 | 既存能力カタログ、保守的なtoken容量計画、短縮ID、選択モデル/推論/送信許可の保持 |
| 通常/超長文 | 一括、端末内、階層統合の既存経路を拡張。通常記録へ追加の計画呼出しを強制しない |
| 並列作文 | 全文と共通計画を使うSoT候補をmock検証。通常利用のgateは閉鎖 |
| 再利用 | 所有者・区間単位のSQLite cache、失効lease、TTL/LRU、変更token付きRAM再利用。現行Knowledgeの根拠を再検証してAsk AI/Project検索へ利用。全文分析済みとは扱わない |
| 通信 | job内session再利用、SSE/JSON off-main、通知抑制、数値診断。実TCP/実APIの改善量は未測定 |
| 送信制御 | 同一endpoint/認証の要約・Ask AI・agent共通上限、優先度/aging、待機上限、429/Retry-After、送信前再認可。明示RPM/TPMの保守的予約。未知値は設定しない |
| 音声準備 | 保存済み音声の1区間先読み変換を候補実装/host検証。通常gateは閉鎖 |
| 確定区間 | 既存STT checkpointへ区間の版/範囲/現行照合を追加。旧cache/本文を維持。先行AI分析は未接続 |
| 評価基盤 | 固定J-MeetEval 197件/16カテゴリ、公式ルール、gold25件、数値集計、比較レポート。raw requestとnative hostの7方式runner、独立spend guard、SSE/SQLite、予算・認可の無料検証。iOS全保存境界/Judge/実生成スコアは未完 |

Geminiは既存OpenAI互換経路。Gemini native API、将来のlocal LLM実行、Memora専用サーバーを実装済みとは扱わない。詳細は[モデル能力表](../MODEL_CAPABILITY_MATRIX.md)。

## 無料で進められる残作業

1. ModelCapabilityRegistryへexact modelに対応したローカルtokenizer/検証済み推定器を接続。未確認比率でcontextを拡張しない。
2. native host runnerのiOS全保存トランザクションへの接続と絶対費用上限の運用検証。7方式のhost実行は無料mockで検証済み。Level 2/3を自動起動しない。
3. Knowledgeの人物・長期記憶・資料等への追加consumer。本人編集/原文参照/権限/訂正/撤回を維持し、未確認解釈を確定memoryへ昇格しない。
4. account別の検証済み並列3/4契約、実メモリ余裕・latencyの観測接続、subscriber別キャンセルを備えたSingle-flight。
5. 引用一致を越えた意味的整合性/網羅性の評価。全UIケースの最終状態での実行と既存警告の解消。

録音中の先行AI分析、ライブSTTによる先行要約、録音中のクラウドAPI呼出しは今回の対象外。
確定区間revisionは保存済み原文の変更検知・再利用のため維持し、先行分析consumerは追加しない。
既存Source Adapter → Canonical input → 既存planner/理解 → SummaryKnowledge → 適応型本文/各consumerを拡張する。

## 未検証・通常有効化しないもの

利用者指定により実モデル評価は行わない。品質/費用/速度の実モデル比較とJ-MeetEval総合スコアは未取得。60秒/30秒の達成は未確認。過去の録音後10〜20秒目標は先行AI分析を前提とする今回の目標にしない。SoTの採用gateは閉じたまま。

実機のSTT/要約/総処理時間、P50/P95、電池、発熱、メモリ、録音安定性、音声への実シーク、VoiceOver/日本語IME/実サービス認証などは別途必要。音声先読みgateも閉鎖を維持する。

PNG復旧UIは既存の機能flagで入口が無効なため未検証。flagや期待値を変更して合格扱いにしない。Jinba品質等の既存未検証項目も維持する。

## 変更単位の記録

- [初回統合検証](VALIDATION_2026_11_15.md): 当時の実装/無料検証/失敗を保存。
- [要約job間の送信制御](SUMMARY_REQUEST_SCHEDULING.md): 追加実装、途中の音声fixture失敗と独立再実行を保存。
- [音声準備候補](AUDIO_PREPARATION_PIPELINE.md): ガード付き全10群/限定E2E/preview成功、候補は通常無効。
- [確定区間の版管理](SETTLED_CHUNK_REVISIONS.md): 今回の追加単位。ガード付き全10群/E2E選択2件/iOS preview成功。実モデル/実機は未検証。

全10群の成功は実モデル品質/実機性能の証明ではなく、限定E2Eの成功は全138 UIケースの成功でもない。

- [共通AI処理の追加改善](../common-ai/IMPLEMENTATION.md): 部分応答ゲート、粒度別cache、共有admission、Knowledge再検証、SoT容量、限定runner。成功/失敗・未完成を分けて記録。
