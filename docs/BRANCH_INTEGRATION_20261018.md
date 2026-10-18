# 未統合ブランチの再評価・前方統合

2026-10-18。開始main `4adc83b`。originをfetchし、追加の未取得mainコミットがないことを確認。
ユーザーの指示は「mainに未取り込みのものを、先祖返りしないように取り込む」。
他worktreeは読み取りで状態を確認しただけで、編集・切替・削除・pushはしない。
確認時点で3つの他worktreeに未コミット変更はなかった。

## ブランチの判断

| ブランチ | 先端 | 判断 |
| --- | --- | --- |
| feat/openui-native-polish | e0b992c | 開始時点でmainの祖先。再適用しない |
| feat/tab-order-askai-thinking | 3eb3aa8 | 通常の3-way mergeで履歴と差分を統合。統合コミット1f9e6f2 |
| memora | 36c97e1 | 現行より古い基点3b5f0fbからの10コミット。mainを解決の基準とし、旧ブランチを親に残すmergeと必要差分の選択移植で統合 |

`memora`はツリーをそのまま採用しない。`git merge -s ours --no-commit --no-ff memora` で
現在の実装を基準にし、以下の有効な差分を個別に前方移植する。
履歴上の統合と、旧機能をすべて同じ動作で有効化することは別。特にHindsightはアプリ機能として未接続のまま。

## memoraの全10コミットの扱い

| コミット | 元の変更 | 現在の扱い |
| --- | --- | --- |
| 2c1bc8e | yomiyasu 1.0.7 | 2.0.1への更新に包含。古い版へ戻さない |
| 0fd02c9 | 会議要約だけに文章規則を適用 | 会話を自然にする意図をAIAnswerPromptへ反映。現行の事実/確度/出典/スキーマ保護の指示を削除しない |
| a77f889 | 会話として自然に回答 | AIAnswerPromptの短文/段落/必要な箇条書きの指示に反映。資料中の命令を実行しない現行ガードを維持 |
| 6be2da9 | 単語単位のrise/点滅カーソル、FlowLayout削除 | 後続でカーソルは取り消し済み。現在のIncremental Markdownと保存済みの即時表示を維持。FlowLayoutを削除しない |
| ff857ac | カーソル削除、回答整形 | カーソルなしは現行で達成済み。整形の意図を新しいprompt/現行Markdown表示へ反映 |
| 0703702 | Hindsightへ自動保存・検索 | 現行のworkspace/送信権限/機微情報/費用/削除失効を満たさないためアプリへ接続しない。4つの元ファイルをtools/reference/memora-hindsightへ完全な参照用テキストとして保管 |
| 92f9cb0 | 全タップ/回答完了の触覚 | タップは現在のInteractionFeedbackの設定・録音中抑制・90ms重複抑止へ接続。成功はsaveAIExchangeの成功回答経路から通知し、停止・失敗の状態遷移では通知しない |
| 87240e5 | 横スワイプにも触覚 | GlobalGestureFeedbackPolicy + GestureHapticsInstallerへ適応。縦スクロール/小さい移動/無効値/同じgestureの2回目を除外。keyboard/入力欄/sliderを除外し、タッチをcancelしない |
| 45e2b51 | 録音tap二重除去と無効formatの防止 | mainのhasInstalledInputTap/isStopped、有限sampleRate、hardware format再照合、変換/所有buffer、bounded streamがより新しい。ファイルを変更せず保持 |
| 36c97e1 | yomiyasu 2.0.1 | 時制・助詞/読点・形式名詞などを取り込み、現行の意味保持・担当者区別・テンプレート保護を残す。version/revisionとMIT全文を更新 |

## 境界

- RootTabのrawValue、UISegmentedControl、3タブ、Ask AIが3番目、右FAB、下部composerを維持。
  起動先を勝手にLibraryへ変更せず、既存のJournal起動と選択復元を維持する。
- 直前の回答メニュー・テキスト選択・長文入力、OpenUI部品、読み上げは置き換えない。
- SQLite/Keychain/録音/バックアップのスキーマ変更や破壊的migrationをしない。
- Hindsightのサーバー/SDK/認証/設定の有効化、会話の自動外部送信はしない。
  保管した元コードのTODOと安全上の理由は参照フォルダのREADMEに記録する。
- yomiyasuのタグv2.0.1はannotated tag `073271758cd42a3ee4ca255bb105cd47b989ee7b`、
  実コミット `1bc21f9c8e6a55fc4ccd5a2c7dfe78a7b0d814c5`。MITを確認し全文をアプリに同梱。
- タブとゲージはMITの既存ChatGPTUI noticeを保持。ブランド素材・新runtime・常時サーバーは追加しない。

## 検証

タブ統合: Debug/Release、optimization、motion-loading成功。タブ順・ライブラリ往復・
処理中/確認待ちの表示・Reduce Motion/Light/Darkの画像は `docs/qa/tab-order-thinking/`。

今回の前方移植: `run-branch-integration-checks.sh` で新しい文章規則、横スワイプの判定、
会話promptの安全指示保持、外部Hindsightの旧自動送信がAppにないこと、現行FlowLayoutの保持を検証。
共通next-generation runnerへ登録した。最終ビルド・全runner・e2eの結果は完了後に追記する。

実機の触覚の感触、録音/マイクとの競合、実モデルの文章品質A/B、実機VoiceOverは未検証。


### 中間結果

- 前方移植後のDebug成功: `2026-10-18T09-04-24-6e08e55e.log`、既存警告11件。
- motion-loading / optimization成功。新しいbranch-integration focused checkも成功。
- UI e2eは既存9件+回答操作/長文入力2件の全11件をキャッシュ無効で実行する。
  APIキー環境をunsetし、テレメトリーを無効化。agent/modelステップは含めない。

### 最終結果

- Debug preview成功、ユーザーのiOSプレビューへ起動済み。
  `2026-10-18T09-04-24-6e08e55e.log`。
- Release simulator成功。`2026-10-18T09-04-25-209014a4.log`。
  両構成とも既存の非推奨API等の警告11件。新規エラーなし。
- next-generation / motion-loading / optimization 全runner成功。
  新規branch-integration checksもnext-generationの最後まで成功。
- Simulator UI回帰11/11成功、失敗・skip・flakyなし。
  run `01a14c54-9158-792b-bc0e-2375eecff9b9`、modelTokens 0。
  タブ往復、設定、capture sheet、task導線、OpenUI比較/Row/streaming/根拠/進捗、
  回答のテキスト選択、長文composerの展開/縮小を含む。
  これは実モデル、実API、録音実行、実機性能のE2Eではない。
- 保護対象12ファイルは統合前 `1f9e6f2` とバイト一致を再確認。
  Hindsight参照4ファイルも元コミットとバイト一致を再確認。
- 触覚の既存SelfChecksには設定OFF、background、録音中、重複抑制の検証がある。
  今回追加した横スワイプは独立host checkで検証。実機での感触・マイク競合は未検証。
- 機械可読な結果は `docs/qa/branch-integration/validation.json` と `e2e.json`。
  チェックと画像は回帰の限定的な証拠であり、全機能・全環境の無退行を保証するものではない。
- merge確定後、対象3ブランチの先端がmainの祖先になったことを確認する。pushは行わない。
