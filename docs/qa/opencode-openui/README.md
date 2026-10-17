# OpenUI ネイティブ仕上げ — 画面QA

このディレクトリは `docs/OPENCODE_OPENUI_NATIVE_POLISH.md` の画面確認用。

現時点で画像は次の10枚（統合後の共有ツリー、iPhone 18 Pro Max / iOS 27.1、
設定 › プロトタイプ › 状態と復旧UIを確認、架空データ）:

比較表（`構造化回答（表示の確認）`）:

- `comparison-dark.png` — 比較表 Dark
- `comparison-light.png` — 比較表 Light
- `comparison-large-text.png` — 比較表 最大文字サイズ（横スクロール）

根拠一覧・進捗（`資料・進捗の表示確認`、`AIInterfaceStructuredExampleView`）:

- `source-list-dark.png` / `source-list-light.png` — 根拠一覧（通常・失効/削除・空）
- `source-list-large-text.png` — 根拠一覧 最大文字サイズ
- `task-progress-dark.png` / `task-progress-light.png` — 進捗（一部完了・全完了・1件のみ）
- `task-progress-dark-expanded.png` — 進捗の内訳を展開
- `task-progress-large-text.png` — 進捗 最大文字サイズ
- `task-progress-reduce-motion.png` — 進捗 Reduce Motion

統合前は worktree（実体 `/Volumes/WorkspaceSSD/Development/Temp/memora-openui-native-polish-20261017`）
を Bitrig がプロジェクトとして認識しないため Debug / Release ビルドとプレビューを
実行できなかった。統合後の共有ツリーで `bitrig preview -platform iOS` が成功している。

未撮影:

- ストリーミング途中（完成部品単位で表示されること）。`AIResponseText` の
  ローカル再生で確認できるが、静的な画面では部分表示を残せない。

元OSSの画面を比較に使う場合は、出典（OpenUI `8d9c4c3b…` の該当ストーリー）と
比較条件を併記すること。Memora の架空データ画面だけを「OSS と一致確認済み」と
報告しないこと。
