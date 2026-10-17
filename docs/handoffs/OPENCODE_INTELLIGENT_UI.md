# OpenCode 別会話へ渡すプロンプト

以下をそのまま渡してください。まだOpenCodeは起動していません。

---

MemoraのIntelligent UI担当として実装してください。別担当はチャット本文・コンポーザーのOSS部分移植を進めています。

## 作業場所と統合

共有作業ツリー `/Users/ken/Library/Bitrig/Users/23515/Projects/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea` では編集・checkout・commitしないでください。
このリポジトリを参照し、実体が開発用SSDにある別worktreeを作り、専用ブランチ `feat/openui-native-polish` で作業してください。既に存在する場合は破壊せず状態を報告してください。最初にベースSHA・実体パス・git状態を記録してください。コード基準は `7d9edb9` 以降。新しいmainから開始して構いません。元のmainを移動しないでください。

AGENTS.md・DESIGN.md・docs/ASK_AI_2_OSS_AUDIT.md・docs/ASK_AI_2_VALIDATION.json・NativeAIInterface/NativeAIInterfaceView・AIPluginExecutionPolicy・AIToolRegistry・既存の実行時参照検証を確認してください。ライセンス情報は古い可能性があるため現行ソースで再確認してください。

## 目標

https://github.com/thesysdev/openui のComponent Library/Streaming/Renderer/状態管理を具体的なソースと画面例で確認し、資料・比較・根拠・進捗の表示品質をネイティブSwiftUIで改善してください。
https://github.com/thesysdev/open-intelligent-ui は画面・操作の参考です。demo自体の転載許諾が確認できなければコード・素材・プロンプトをコピーしないでください。OpenUI本体MITとdemoの権利を混同しないでください。

単なる調査で終了せず、まず既存ComparisonTable/SourceList/TaskProgressの余白・階層・展開操作を改善し、必要なら読み取り専用のRow/Column/Disclosure配置を限定スキーマで追加してください。不要なカードを増やさず、タスク/資料/日程の実在IDから表示します。新しい汎用フォーム・任意式評価・HTML/JS・遠隔画像ロードは今回対象外です。

## 編集してよい範囲

- App/NativeAIInterface.swift、App/NativeAIInterfaceView.swift
- App/AIInterfaceTaskProgress.swift。比較表・根拠一覧は現状NativeAIInterfaceView内のcaseであり、必要なら新規AIInterfaceComparisonTable/AIInterfaceSourceListへ抽出して構いません
- 新規 App/AIInterface* の表示部品
- tools/checks/OpenUINativePolishChecks.swift、tools/checks/run-openui-native-polish-checks.sh
- docs/OPENCODE_OPENUI_NATIVE_POLISH.md と docs/qa/opencode-openui/ 以下

上記以外を変更する必要があれば、変更せず統合担当向けの必要差分を報告してください。既存のテストランナーや全体ドキュメントは統合担当が接続します。

## 別担当の専有範囲（変更禁止）

AIResponse*、StreamingMarkdownView、MarkdownBlock*、AIAnswerActions、AIMessageView、AIComposer*、QuickAIComposer、SearchView、StateGalleryView、RootTabView、MemoraModel*、Agent*、Project.json、Shared/*、全体のOSS/進捗/検証ドキュメントと共通テストランナー。

## 保護条件

- iOS26以上、SDK27.1。SwiftUIネイティブ・モノトーン・Liquid Glass・既存3タブ/FAB/空白新規チャットを維持。
- MemoraModelが唯一の実データ。UI一時状態だけViewに保持。権限/承認/コストを表示JSONから増やさない。
- ストリーミング中は書き込み操作無効。完成部品だけ検証して表示。既存の安定ID・有効表示保持・キャッシュ・出典処理を維持。
- 操作は既存registry/承認へ渡す。保存履歴から実行権限を復活させない。非公開化/削除/ワークスペース切替時の実行時検証を弱めない。
- 実APIキー/個人データ/外部課金/実アカウント操作/本番デプロイは禁止。新しいサーバー・テレメトリー・JS依存は追加しない。
- コピーするMITコードは固定SHA・元ファイル・著作権・ライセンス全文を記録。ブランド素材は持ち込まない。

## 検証と成果物

架空データで通常/長文/空/途中ストリーム/不正JSON/失効IDを検証し、ホストテストと可能ならDebug/Release、Light/Dark/大きい文字/Reduce Motionの画面を確認してください。
Bitrigが別worktreeで使えない場合はその制約を記録し、統合担当にビルドを依頼してください。他のツリーで動作しているプレビューを上書きしないでください。

小さいコミットに分け、最終的に「ベースSHA・コミットSHA・変更ファイル・実行した検証・未検証・移植元とライセンス・統合が必要な箇所」を報告してください。push/merge/cherry-pickは行わないでください。ビルド成功・画面再現・実サービスE2Eを別々に報告してください。
