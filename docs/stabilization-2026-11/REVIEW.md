# Memora 全体安定化レビュー

2026-11-16開始。全Phase完了の報告ではなく、開発単位ごとに証拠と残作業を追記する。

## Phase 0: 現在の正本

- 開始HEAD: `987b37ef`、main。未コミット差分なし。GitHub `github/main` とBitrig `origin/main` をfetchし、双方との差分0を確認。
- 正本: AGENTS.md、DESIGN.md (2026-11-14)、MCP.md、各domain文書。旧RN版の設計は適用しない。
- SQLite (`LocalStore` / `RecordStore`) が記録・会話・派生cacheの保存先。音声/写真は `MediaFiles`、設定だけUserDefaults。新しいDB/移行は計画しない。
- `tools/supervisor/run.py` で正確なallowed filesを指定しOpenCode Goへ委譲。独立レビュー、最大2修正、既存gateを維持。

## 既存実装と調査単位

| 領域 | 既存の処理/正本 | 確認済み状況・次の検証 |
|---|---|---|
| Live | AIComposerBar / LiveConversationSession / LocalVoiceLLM / LocalVoiceModelStore | 入口flagなし。composer生成で音声関連object/Observerを構築。LLM contextは保持し続ける。最優先修正 |
| 録音・取り込み・STT | RecordedAudioTranscription / SourceMediaAudioLease / checkpoint revision | 共通保存済み入力の処理、確定prefix再開、容量制限あり。先読み候補はgate閉鎖を維持 |
| 要約 | SummaryRequestAdmission / SummaryArtifactCache / SummaryCompositionPlan / SummaryProviderAdapter / SummaryOptimizationGate | 既に容量計画、部分再利用、送信制御、provider互換あり。重複実装せず無料10群で検証 |
| 要約品質 | SummaryKnowledge / source fingerprint / J-MeetEval / tools/evaluation | 固定197件、gold25件、native runnerあり。mockと実モデル品質を区別。有料評価は実行しない |
| 知識/RAG | MemoraModel+SummaryKnowledge / ProjectSearchIndex / 人物・memory・conversation | 既存正本と失効境界を調査しconsumer不足を特定。抽出事実を確定memoryへ自動昇格しない |
| Ask AI | ConversationScrollFollowing / ConversationScrollState / streaming / admission | geometry更新で自動scrollを要求する既存実装を確認。再現・状態テストから改善単位を決める |
| 外部取り込み | Source adapters / ProjectSourceStorage / extraction cache | 元データ変更、権限、保存失敗を既存host checksで確認 |
| agent/MCP | scoped runtime / 承認・endpoint/fingerprint/費用check | 承認境界を維持。新規外部副作用や実サービス操作なし |
| 資料 | SlidePageLayout / PPTXWriter / Jinba比較文書 | 65種の実装・レンダリング比較は追加調査。生成成功だけを品質証明にしない |
| UI/性能 | DESIGN.md / 既存共通部品 / 診断tools | 承認済みUIを維持。Live非表示と保存容量からのモデル削除だけを当面の明示UI変更とする |
| セキュリティ | Keychain / workspace・privacy lease / backup | 実装調査と無料回帰で確認。実認証・配布・アカウント削除は未検証として残す |

## テストの開始状態

`docs/common-ai/UI_TEST_STATUS.json` の直近の統合記録は138件発見、8成功、0失敗、130未実行。
理由は限定offline subsetのみの実行。現在HEADの合格証拠ではない。
後続の個別報告や過去の成功を全件成功として合算しない。
既存host集約runnerは10群で、実行前後の内容hashとfile revisionを比較する。

## 実行順序と合格条件

1. Live通常無効化: UIと実行入口をflagで遮断。音声入力/録音/読み上げ/録音Live Activityを保持。
2. Live resource寿命: idle初期化なし、安全なload/generation失効と解放、既存modelを自動削除しない。本人操作でのみ削除。
3. host/シミュレーター確認: 同じ最終sourceで実行、失敗/未実行を保持。必要なテストfixture修正は本番仕様から独立レビュー。
4. 次のbounded単位: streaming scroll、知識consumer、全体回帰/セキュリティ・資料の順で実際の不足を修正。

## 現時点の制限

1時間原文の60秒/30秒、実API品質、実機STT/電池/発熱/ピークメモリは未測定。
モデルdownload・有料API・実ユーザーデータ外部送信・実機操作は検証として実行しない。
全Phase、全画面レビュー、138件全実行、Jinba再現性は未完了。
