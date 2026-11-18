# Memora 全体安定化レビュー

2026-11-16開始。全Phase完了の報告ではなく、開発単位ごとに証拠と残作業を追記する。

2026-11-19: ユーザー指摘を優先しAsk AIの回答表示を修復。
`5028b0ca` で生成UIの二重スクロール・伸縮と、長文で隠れるDialogを修正した。
最終ビルド成功、host 2グループ + JS/DOM 12件 + UI E2E 5件成功。
UI全140件のうち残り135件の合格を意味しない。
比較画像・原因・互換性・未検証範囲は [回答表示の検証報告](ASK_AI_DISPLAY.md) を参照。

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

## Phase 1 / 単位1: Live入口の無効化

OpenCode Goへの6ファイル限定委譲。run `run-wefqqtor`、初回候補でmotion policy、motion/loading回帰、
隔離iOS全体ビルド、独立Codexレビュー（findings 0）を通過。監督が実差分を再レビューして反映した。

通常Debug/Releaseはflag false。開発用の `DEBUG && MEMORA_ENABLE_LIVE_CONVERSATION` だけtrue。
composerはLive sessionを生成せず、idle波形/panel/setupを非表示。start/chat/LLM/installも処理前に拒否する。
Intent/Deep Linkに別のLive起動入口は見つからなかった。録音Live Activityは対象外。
SQLite/schema、BYOK、記録/音声/写真、既存GGUF、依存関係は変更しない。

- `run-live-feature-checks.py`: 4コンパイル条件成功、Debug/Releaseで本番LLM/downloaderの各100回拒否成功。
  native・file・network到達はstubで失敗させる。実native推論や実ダウンロードではない。
- `test_quality_runner.py`: 9成功、失敗0。Liveを通常集約runnerの11番目の群として追加。
- composer-layout、既存Live制御、UTF-8/promptの回帰成功。
- `bitrig preview -platform iOS`: 成功、既存11警告。log `2026-11-16T07-39-08-9806f429.log`。
- built-in simulator: Liveボタンなし、通常micあり、入力で送信表示、通常モデルsheet、閉じた後のdraft保持をAXで確認。
  [変更前](screenshots/live-before.png) / [無効化後](screenshots/live-disabled.png)。前者はLive失敗panel、後者は通常チャット。
  日本語のtypeTextはsimulator toolが非対応で拒否したため、ASCII検証入力を使用。日本語IME実操作の合格証拠にはしない。

安全なモデル解放、停止/ロード競合、保存容量からの本人削除は単位2で実装する。全Phase完了ではない。
