# Ask AI Next Generation 実装・検証記録

## Phase 0 — 基準 (2026-10-16)

`git fetch github main` / `git fetch origin main` 実施。開始SHAは
`af3007cbe73585e180c33982b206d1e9c846c408`。両remoteのmainとHEADが一致。
AGENTS.md / DESIGN.md / MCP.md / docs/NEXT_GENERATION_AI.md / 現行コードを照合。
DESIGN.md後半には旧4タブ、サンプルfallback、モデル選択UIの記述が残る。
現行AGENTS.mdと実装（Home / Library / Ask AI、実行不可は失敗表示）を優先する。

要求された34ファイルは現在のApp内に存在。既存Swift agent harness、有限予算、
ストリーム終端検証、承認、MCP endpoint/credential/cost確認、SQLite record store、
FTS5プロジェクト検索、日本語2-gram、PDF/PPTX、添付OOXML抽出を再利用する。
通常レコードはSQLiteのJSON文書、音声/写真/添付はコンテナ内ファイル参照。
設定だけUserDefaults、APIキーはKeychain。破壊的なスキーマ移行は行わない。

### 改善前に確認した不足

- person(named:) / cloud用automaticRecordToolのread_personは部分一致の先頭を選ぶ。
- cloud経路は既に会議の送信許可を絞るが、人物ID指定・十分な出典管理・
  タスク/ジャーナルを含む人物情報の統一的取得がない。端末内の豊富な人物集約は
  名前の確度だけで別人を結合し得る。人物画面の質問は名前だけでglobalへ送る。
- explicit semantic memoryは200字のAIMemory。時点/状態/スコープ/矛盾履歴がない。
  過去履歴の関連検索は単語一致。cloudは別のprovenance確認を使う。
- snapshotは中断処理を実行せず復元するが、会話ID/人物スコープを保持しない。
- Skillは3件、@候補とチップは汎用プラグアイコン。チップ全体が削除ボタン。
- Officeはbounded抽出のみ。DOCX書出/企業テンプレート差分生成は未実装。
- MailDraftは一時値。Memora内の永続下書き/編集一覧はない。
- Gmailはreadonly OAuth。Drafts APIへの書込権限は取得していない。
- Deep ResearchはBraveの検索/レポート基盤があるが有限の追加調査を強化できる。

### OSS判断

全指定24リポジトリの公開GitHubメタデータを取得し
[ASK_AI_OSS_AUDIT.json](ASK_AI_OSS_AUDIT.json) に取得日時・root SPDX・archivedを記録。
これは推移依存全体の法務承認ではない。第三者コード/Skill素材をアプリへコピーしない。

|候補|確認/判断|
|---|---|
|Mem0 / Graphiti / Cognee / Letta|Apache-2.0。Python/サービス/モデル・グラフ等の依存と運用が必要。設計参考のみ。Swift+SQLiteを維持|
|LangMem|MIT。LangGraph/Python依存。設計参考のみ|
|TencentDB Agent Memory|API上NOASSERTION。root本文/各componentの再確認が必要。未採用|
|Supermemory|root MITと配布・サービス利用条件を分ける。root表示だけで全componentの再配布許可とは判断しない。未採用|
|python-pptx / python-docx|MIT。Python/lxml/Pillow等。iOSへ組込まず独立ローカルPoC候補|
|docx-cli / docx-template-skill / pydocxtpl|root MIT。CLI/Skill/依存条件が別。アプリへコピーしない|
|ppt-master|root MIT。任意のAGPL処理を依存全体から区別。未採用|
|python-docx-template|LGPL-2.1。配布/改変/依存の追加評価が必要。標準エンジンには未採用|
|anthropics/skills / awesome-claude-skills|rootから一括許諾を確認できない。個別素材の制限を尊重し手順を独自記述|
|superpowers|MIT。手順設計を参考にするが実行環境は取り込まない|
|dzhng/deep-research|MIT。search→不足→追加searchの有限ループを参考。Firecrawl/LLM等の費用は別|
|open_deep_research|MIT、今回の取得でarchived=true。設計参考のみ|
|Skywork / Alibaba / qx-labs / Cranot|root MIT/Apache。Python/Nodeと検索・LLM依存。既存Swift調査を維持|
|DeepSeek Harness|MIT。既存Swift harnessを置換しない|

オンデバイスEmbeddingはApple NaturalLanguage等の言語/モデル対応、端末容量、
日本語精度を別途測定すべき。今回はFTS5/2-gram/時点/厳格scopeを優先し、
ベクトルDBや新規常時サーバーを導入しない。運営者への新規固定費はない。

### 検証方針

既存3チェックrunnerを再利用し架空fixtureを追加。build/previewはbitrigのみ。
実アカウント、実記録、有料APIは使用しない。Debug/Release成功と実機性能は別。
外部の実接続、iPhoneの実録音/背景実行/メモリ性能は未検証として残す。
