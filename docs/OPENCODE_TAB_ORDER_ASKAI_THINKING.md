# タブ順の入れ替えと Ask AI 経過表示（ChatGPT 参考）

2026-10-17。所有者の依頼による2点:

1. ジャーナルとライブラリのタブ位置を入れ替える。
2. Ask AI の経過（処理中）表示を ChatGPT を参考にする。

Intelligent UI レーンの成果（ComparisonTable / SourceList / TaskProgress）は
すでに main に取り込まれているため、本作業は現行 main から新しく開始した。

## 作業場所

- 参照元（共有ツリー、編集しない）:
  `/Users/ken/Library/Bitrig/Users/23515/Projects/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea`
- 実作業 worktree（実体は開発用SSD）:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-tab-askai-20261017`
- ブランチ: `feat/tab-order-askai-thinking`
- ベースSHA: `fd7bbc0a1d8253b9c73d65f80a94bd9f441237aa`（現行 main）
- 元 main・共有ツリー・既存 worktree は変更していない。

## 変更

### 1. タブ順（RootTab）

`RootTab` の宣言順を `library, home, askAI` に入れ替えた。`ProminentTabBar` は
`RootTab.allCases` の順でセグメントを並べるため、これで下タブが
「ライブラリ → ジャーナル → Ask AI」になる。Ask AI は3番目のまま。
rawValue（`files` / `home`）は変えていないので、保存済みの選択はそのまま解決する。

- `App/RootTab.swift`: 宣言順の入れ替え（コメントで理由を記載）。
- `App/SelfChecks.swift`: タブ順の自己検査を新順 `[.library, .home, .askAI]` に更新。

`RootTabView` の `TabView` 内容順は元から library → home → askAI（タグ駆動）で、
変更不要。`RootTabView` と `ProminentTabBar` は触っていない。

### 2. Ask AI の経過表示（ConversationStatusLine）

処理中の行頭に、ChatGPT 風の丸いゲージ（`ThinkingGauge`）を表示する。
現行は SF Symbol の `sparkle` を置いていた。ゲージは:

- 灰色の下地アーク＋アクセントのアーク＋中心の点＋針。
- 処理中はアクセントのアークが回転する。
- Reduce Motion では回転しない。
- 承認待ち（`isWaiting`）では回転を止め、人の回答を待っていることを示す。
- 装飾なので VoiceOver からは隠す（ラベルと経過秒は従来どおり読み上げる）。

`ConversationStatusLine` は `AIQuestionView` / `ThinkingTraceView` /
`ProjectChatView` の Ask AI 系でのみ使われる。経過秒（`ElapsedText`）と
シマーはそのまま維持した。

## OSS の参照とライセンス

- 参照元: chatgpt-ios-ui `dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1`（2026-10-10）、
  `Sources/ChatGPTUI/Design.swift` の `ThinkingGauge`。
- ライセンス: MIT、`Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors`。
  ライセンス全文は既存の `App/Resources/ChatGPTUI-LICENSE.txt` に同梱済み。
- 変更内容: 形状（トリムした円弧2本＋中心点＋針）を移植し、Memora の
  モノトーンパレットに置換、処理中の回転と Reduce Motion / 承認待ちの停止を追加。
  元ファイルの著作権表示とライセンス参照をソースコメントに記録した。
- ブランド素材・画像は持ち込んでいない。

## 検証

- `swiftc -parse`（`RootTab.swift` / `SelfChecks.swift` / `ConversationStatusLine.swift`）→ 成功。
- `ConversationStatusLine` を実 iOS 27.1 SDK に対して `swiftc -typecheck`
  （`ElapsedText` のみスタブ）→ 成功。**ビューが型検査を通ることの確認であり、
  アプリのフルビルドや描画確認ではない。**
- 回帰確認: `run-openui-native-polish-checks.sh`、`run-intelligent-ui-checks.sh` → 成功。

## 未検証・統合担当への注意

- **Bitrig はこの worktree をプロジェクトとして認識しない**ため、Debug/Release
  ビルド・プレビュー・スクリーンショットは未実施。共有ツリーのプレビューは
  上書きしていない。統合担当が統合後のツリーで確認する。
- `AGENTS.md` の「タブ順は Home, Library, Ask AI」という記述は今回の変更で
  古くなる（新順: Library, Home, Ask AI、Ask AI は3番目）。AGENTS.md は
  共有ドキュメントのため本レーンでは編集していない。統合担当が更新すること。
- タブのラベルや順序に依存する e2e / スナップショットがあれば更新が必要。
- VoiceOver の読み上げ、Light/Dark、大きい文字、Reduce Motion の実機目視は未検証。
