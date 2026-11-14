# Adaptive Structured Summary — 開発記録

基準・開始HEAD: `342094666b366f5420bfe09d48f478ba08ea30ea`、main。origin取得後も同一。開始時クリーン。

## 責務と正本

1. Content Understanding: 既存MeetingSummaryInputの取得範囲・話者・原文のみを理解する。キーワードによる分類は候補提示だけ。
2. Structured Knowledge Extraction: MeetingSummaryの抽出結果を既存TemplateSummary履歴へ保存。本文と同じ生成応答から取得。未言及と明示保留を区別。
3. Adaptive Composition: content.adaptiveを全組み込み用途へ拡張。各用途のfocus/sectionsは抽出観点。カスタムの明示形式は保持。
4. Presentation / Integration: 本文を主表示。既存タスクは独立したユーザー管理データとして保持。古い抽出は編集後に最新とみなさない。

LLM呼出し: 通常クラウドは既存の1回を維持。長文は部分抽出→階層統合→最終生成を維持。端末内は既存の分割guided generationを使用し、通常プロファイルの再分類呼出しを廃止する。クラウドへの自動フォールバックは追加しない。

## 単位

- A: 適応型プロンプト、全既存プロファイル、生成時構造検証、端末内組立。
- B: 状態・根拠付き抽出、後方互換履歴、保存と編集の整合、資料経路。
- C: 本文中心の画面、抽出情報確認、原文リンク、Markdown表とアクセシビリティ。
- D: AskAI/検索/外部出力の整合と全体回帰、35シナリオ、比較、UI/E2E。

## 初期調査

- SummaryPrompt.marketFormat/automaticCandidatesは固定見出しと「記録なし」を要求。built-inも反復構成。
- SummaryMarkdownBuilderは空配列を「なし」に変換。OnDeviceSummarizer.templateDocumentも空欄を表示。
- 既存content.adaptiveは原文に応じた構成を実装済み。別エンジンを作らず共通化する。
- 要約保存は記録・タスク・pending jobをSQLite同一transactionで確定。SummaryJobFingerprintは編集/削除/許可変更を拒否。維持する。
- タスクは件名で再抽出の重複を拒否し完了状態を保持。要約本文編集はタスクを変更しない。
- TemplateSummaryは本文・構造化リスト・根拠を履歴に保持。SummaryEvidenceLinkはsegment IDと原文完全一致で再検証する。
- ProjectSourceはMeetingSummarizerを共用。Web/PDF/Office/字幕の取得範囲をinputへ渡す。ジャーナルrecap/weekly reviewは原文からのローカル生成でありLLM要約ではない。
- 初期カタログはmarket **55種類** + built-in **4種類** = **59種類**。すべて保持・検証対象。

## 基準検証

- bitrig preview iOS: 成功、既存warning 11件。
- host quality: design-refresh/background-summary/summary-reliability/composer-layout/optimization成功。
- next-generation: 既存fixtureがGitHub/Linear変更に追従せずmcpServers未定義でコンパイル失敗。変更前の既知不整合として修正する。
- 基準ログ: `/Volumes/WorkspaceSSD/Development/Agents/MemoraAdaptiveValidation/baseline-3420946`。
- OpenCode run-ym3mtgrv: ワーカー20分timeout。ゲート未実施、未適用。候補コードを流用しない。後続の狭いタスクで再委譲する。

## 未検証（実施時のみ更新）

実クラウド/DeepSeekの内容・実トークン/料金/遅延、実機録音、実サービス認証、Jinbaの資料品質は未検証。fixtureの合格はこれらを意味しない。実LLM呼出しに実費や原文送信を伴う場合は既存の承認境界を守る。

## A 実装・レビュー

通常の全59プロファイルを適応型へ統一。既存focus/sections/IDは保持し、カスタムの明示形式のみ固定。候補は最大8件、モデルは最大3観点を組合せる指示とした。通常クラウド呼出し数は変更なし。
端末内は通常プロファイルの再分類生成を廃止し、既存topic抽出→共通builderを利用。空項目は出さず、担当・期限を補完しない。
生成時限定の構造検証を追加。本文/原文の保存・表示・編集時には実行しない。全体の文字列置換による「なし」削除はしない。
動的な話題名に「決定」を含むだけで抽出していたMarkdownフォールバックを修正。既知の意味付きラベルだけを読む。理由/条件付きの点は重複削減の対象外として意味を保持。

検証: SummaryPrompt/Layout/Relation/TemplateNotes/Pipeline、生成Markdownの12種の構造/保持/idempotence検証、編集SQLite失敗・競合・再読込、Infographic回帰を実行。iOS preview成功（既存warning 11件）。実モデル内容評価・UI全項目は後続。
