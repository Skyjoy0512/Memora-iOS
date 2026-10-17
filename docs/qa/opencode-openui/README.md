# OpenUI ネイティブ仕上げ — 画面QA

このディレクトリは `docs/OPENCODE_OPENUI_NATIVE_POLISH.md` の画面確認用。

現時点で画像は次の3枚（統合後の共有ツリー、iPhone 18 Pro Max / iOS 27.1、
設定 › プロトタイプ › 状態と復旧UIを確認 › 構造化回答、架空データ）:

- `comparison-dark.png` — 比較表 Dark
- `comparison-light.png` — 比較表 Light
- `comparison-large-text.png` — 比較表 最大文字サイズ（横スクロール）

統合前は worktree（実体 `/Volumes/WorkspaceSSD/Development/Temp/memora-openui-native-polish-20261017`）
を Bitrig がプロジェクトとして認識しないため Debug / Release ビルドとプレビューを
実行できなかった。統合後の共有ツリーで `bitrig preview -platform iOS` が成功している。

未撮影（`NativeAIInterfaceExampleView` に含まれないため）:

- 根拠一覧: 通常 / 長い資料名 / 失効・削除された資料 / 空状態 / Light / Dark
- 進捗: 一部完了 / 全完了 / 内訳の展開 / 1件のみ / Reduce Motion
- ストリーミング途中（完成部品単位で表示されること）

元OSSの画面を比較に使う場合は、出典（OpenUI `8d9c4c3b…` の該当ストーリー）と
比較条件を併記すること。Memora の架空データ画面だけを「OSS と一致確認済み」と
報告しないこと。
