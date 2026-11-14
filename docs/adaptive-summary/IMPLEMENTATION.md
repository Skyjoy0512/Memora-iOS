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

## 既存ホストfixture修復

OpenCode Go / DeepSeek run-waun4b4rを実行し、NotionAgentFixtureModelのmcpServers初期状態1行だけを許可・反映。初回でscope/diff/motion/regression/iOS全体build/監督review合格。監督側でNotionAgentChecksも実行し、188 agent race +45 manual race合格。実サービス認証の検証ではない。

## B 状態・根拠・履歴・保存

SummaryKnowledgeをTemplateSummaryの任意拡張として追加（履歴schemaVersion 3）。既存Meetingの本文/リストを正本として維持し、取得範囲に限ったcoverage、6状態、話題/事実ID、関連事実、検証済み引用を保持。追加部分の破損は項目単位で読み飛ばす。旧データは再生成・書換えしない。
原文fingerprintと本文/リストの一致で利用可否を判定。ユーザーがリストを編集済みなら再生成で上書きせず、抽出と再調整した履歴であることを保持。開始後のリスト編集もjob fingerprintで拒否。既存タスクの完了・担当・メモは件名一致の再抽出で変更しない。
クラウドは既存1応答へknowledgeを付加。JSON切断・不正な抽出ブロックは確定保存しない。追加の課金retryはなし。根拠のID/引用は原文照合し、不正な参照を除外して要確認にする。見出しだけで根拠を恒久結合しない。同名節の曖昧な旧参照は結合しない。
端末内は簡潔な状態付きfact schemaを既存digestに追加。短い記録は同じdigestから見出し・概要を構成し、通常1回の呼出し。原文の引用が一意な場合だけ実IDへ結合。クラウドfallback追加なし。
ProjectSourceも任意のknowledgeを保持。source UUIDと原文block順序から安定したsegment UUIDを作る。原文referenceの一致が前提。未取得ページや図表は補完しない。

検証: AdaptiveSummaryKnowledgeChecks、background queue/atomic save/reopen（完了済タスクと本人の訂正保持、生成中リスト編集の拒否を追加）、source summary13競合、summary reading全群が合格。iOS preview成功。新しいCodable依存をホストsuiteに明示しているためharnessのsource listも更新。全体qualityは継続中。
E2E旧summary-recoveryの1ケースは保存失敗後に原文表示を期待して失敗。SQLite原本は不変、画面とdraftは失敗した編集を保持しており現行の仕様と整合。後続ではDB・draft・未保存表示の3点を検証し、原文の喪失と混同しない。

## C 読書・操作・UI

本文の下へ無条件に再掲していた決定/未決/要点を削除し、その他→抽出情報を確認から既存編集とタスクへ到達可能にした。未言及はこの補助画面だけで表示。生成時情報と編集後の失効を明示。原文参照は音声なしでもsegment IDで正確な発言を開く。
本文と資料の先頭H1は読み取り表示でのみ省略（保存文字列と編集位置は維持、タイトルだけの文書は隠さない）。Markdown表は読む/セル編集の両方で同じ横スクロール配置。Dynamic Typeで本文を拡大しながら、字下げと表列幅が無制限に広がらないよう上限を設けた。新しいFABやカード装飾なし。
E2Eでタスク保存後に一覧が更新されない実不具合を再現。tasks(forMeeting:)のcache hitでも元配列のObservation依存を登録し、同一テストが合格。
新E2Eは生成fixtureの初回表示・本文・下部AskAI/capture非表示・原文参照（音声なし）・タスク追加/完了/SQLite原文不変を検証し、81.31秒で合格。UIKitに挿入caretがあってもAX focusがfalseのケースは、fixture入力を実際の文字列値と保存結果で検証する形に修正。期待値だけでアプリのタスク不具合を隠していない。
旧summary-recoveryの保存失敗テストは、原本DB不変＋未保存draft表示＋再試行を要求する形に修正（再実行は後続）。
実プレビューでライト/ダークの本文、表の左右scroll、最大Dynamic Typeを観察しスクリーンショット保存。未取得の画面を検証済みにはしない。iOS preview、11個のpresentation静的テストとUI interaction policy合格。

## 既存統合テストの追加修復

Gmail fixtureにもmcpServersを追加。古いchangesData引数のpreconditionは本番から既に削除されたAPIをモデル化していたため、本番と同じ1引数の承認APIへ合わせた。135の承認/接続/取得race合格。
カレンダー/資料のPersonFixtureも本番MCPServerConfig/MCPTool型を参照するよう更新。54の所有権/許可変更とOFF/ON再検証、cloud/端末内のカレンダーpreview/承認/失効検証合格。fixtureの状態を本番へ合わせた変更であり、権限・承認の本番ロジックは変更していない。
