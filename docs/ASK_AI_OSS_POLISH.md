# 指定OSSの部分移植・画面比較

2026-10-17。開始時のMemora: `7d9edb9`。全画面の再現完了を意味しない。

## 設計参考からコード部分移植へ

初回調査では独立実装だった。今回、次のMITコードをMemora用に変更して取り込んだ。

移植元: [ChatGPTMarkdownView.swift](https://github.com/bryanrg22/chatgpt-ios-ui/blob/dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1/Sources/ChatGPTUI/ChatGPTMarkdownView.swift)

| 元の部品 | Memoraの適用先 | 取り込んだ点 / 適応 |
| --- | --- | --- |
| ChatGPTCodeCard | AIResponseCodeBlock | 16pt内側余白、18pt間隔、24pt角丸、薄い輪郭、水平スクロール。44ptコピー・キャンセル可能な確認表示・Dynamic Type・モノトーンはMemoraへ適応 |
| tableWidths / tableRow | AIResponseTableLayout / AIResponseTable | 内容量に応じた列幅、行ごとの区切り、12pt上下余白。日本語・極端な長文の重み制限・拡大文字の最小列幅を追加 |
| blocks / inline / quote / theme | StreamingMarkdownView / AIResponseMarkdownBlock | ブロック間22pt、本文行間5pt、引用の17pt字下げと4pt線。見出し・箇条書き・既存インライン出典は維持 |

著作権: Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors。
MIT全文を `App/Resources/ChatGPTUI-LICENSE.txt` に同梱。商用配布時も保持する。
Package/ChatState/ブランドロゴ/素材/swift-markdown/cmarkを追加していない。
OpenUIとopen-intelligent-uiは今回コード移植していない。後者のdemoの転載許諾をMIT本体から推定しない。

この変更はチャット回答だけに適用する。編集可能な会議要約・保存済み文書の描画方式、SQLite形式、
MemoraModel・権限・承認・出典URL検証・メッセージと完成ブロックの識別は変更していない。
表の文字数は組版測定ではなく幅配分の近似。元OSSの配置に合わせつつ、字形やDynamic Typeで差が生じる。

## 比較方法

設定 › プロトタイプ › 状態と復旧UIを確認 › OSSの部分移植（表示比較）。Debug限定。
同じ架空の依頼・回答を「従来 / OSSを反映」で比較する。従来は7d9edb9の描画形状の表示専用固定版。
変更後は実際のAIResponseText/StreamingMarkdownView/コード・表のproduction部品を使用する。
この比較はMemora変更前後であり、OSSのデモを起動した比較や、ChatGPT実アプリとの一致度測定ではない。
途中表示はローカル文字列の再生。実プロバイダーのストリーミングE2Eとは区別する。

## 並行開発

OpenCode実行ファイルの存在を確認した（`/opt/homebrew/bin/opencode`）。認証・モデル接続・課金は未確認。
[別会話用プロンプト](handoffs/OPENCODE_INTELLIGENT_UI.md)を用意したが、起動していない。
別worktreeでOpenUI由来のIntelligent UI改善を担当し、こちらはチャット描画/コンポーザーを担当する。
同じBitrig作業ツリーの別会話で同時編集しない。許可された差分をコミット単位でレビュー・統合する。

## 未完了

- chatgpt-ios-uiの全メッセージアクション、コンポーザー、履歴、音声表示の品質移植と比較。
- OpenUIを基準にした成果物・比較・根拠・配置の改善と接続。
- 実機VoiceOver、長い実会話のFPS/メモリ/IME、実サービスE2E。
- 元OSSデモそのものを起動した同条件スクリーンショット比較。ブランド素材は取り込まない。

## 検証記録

- `run-answer-presentation-checks.sh`: 成功。日本語・拡大文字・不正/狭い幅・空/不揃い/大量/長文セル。
  共通のnext-generationランナーにも登録した。
- `run-intelligent-ui-checks.sh`: 成功。完成部品の途中表示、旧形式、安定ID、未知操作/不正JSON拒否。
- `bitrig preview -platform iOS`: 成功、既存の警告11件。Debugログ `2026-10-17T18-49-46-270fae8e.log`。
- `run-motion-loading-checks.sh`、`run-optimization-checks.py`: 成功。

性能改善率やOSSとの画面一致率は測定していない。新しい有料API・実ユーザー記録の検証利用なし。

- Releaseビルド: 成功、既存の警告11件。ログ `2026-10-17T18-49-48-f775eb65.log`。
- iPhone 18 Pro Max / iOS27.1: 同じ架空回答のLight変更前後、Dark変更後を視覚確認。
  コードコピーのチェックマーク、部分テキストから完成回答への再生、最大Dynamic Typeでの表の
  横スクロールを確認。Reduce Motionも有効にして表示を確認し、検証後は標準文字サイズへ復帰した。
  VoiceOverの読み上げ、ペーストボード値の別アプリでの照合、実通信の最初のトークン時間は未検証。
- 画面: [従来Light](qa/askai2/oss-polish/before-light.png)、
  [変更後Light](qa/askai2/oss-polish/after-light.png)、
  [変更後Dark](qa/askai2/oss-polish/after-dark.png)、
  [最大文字サイズの横スクロール](qa/askai2/oss-polish/large-text-horizontal.png)。

共通next-generationランナーの初回実行は、登録中のファイル更新でシェルの読み位置がずれ、
67行目でcommand not foundとなった。アプリやテストのアサーション失敗とは別である。
以後スクリプトを固定して全体を再実行し、その最終結果を採用する。

最終 `run-next-generation-checks.sh` は終了コード0で成功
（`/tmp/memora-oss-polish-next-final.log`）。追加の表組みチェックもこの再実行に含む。
既存のクラウド通信モック、タスク操作の承認/保存、カレンダー参照失効チェックも成功。
