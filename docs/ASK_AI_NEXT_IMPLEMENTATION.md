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

## Phase 1 — 人物・会話の境界

PersonIdentityで完全一致を優先し、部分一致も1件だけの場合に解決する。
同姓/同名はID付き候補を返して確認する。read_personにperson_idを追加し、
cloud/常駐の両方で共通の人物読取へ統一。会議・タスク・ジャーナルの送信可否を
別々に確認し、読んだrecord fingerprintを保持する。現在の実行中も内容編集/
削除/権限失効で次のモデル呼出を止める。独立した送信許可がない人物メモは
cloudへ自動送信しない。人物metadataを含む結果は再利用検証未完了として扱う。

人物画面からはID固定の専用会話を開始。参照候補は参加者タグの記録に限定。
文字起こしの名前だけでは同一人物と断定しない。タスクの名前照合は同名人物が
いない時だけ使用（旧taskはpersonIDを持たない）。人物会話でGmail/MCP等は
提供せず、資料/下書きだけ通常の承認を経て保存可能。ヘッダーメニューでglobalへ
戻る。会話ID/人物IDをoptionalでsnapshotに追加し旧形式を維持。
端末内の人物会話でも同じ安全側の送信許可フィルターを用いるため、未許可の
ローカル記録を扱う拡張は残る。会議の決定は本人の合意と表現しない。

検証: PersonIdentityChecks成功。run-next-generation-checks.sh全スイート成功。
Debug preview成功: 2026-10-16T19-22-53-35668aa7.log (既存metadata警告1件)。
実クラウド・実人物・実記録を使うE2Eは未実施。

OSS補足: TencentのGitHub SPDXはNOASSERTIONだが取得したLICENSE本文ではMITを
確認。Supermemoryのroot MITと、商用/配布制限のcomponentは同一視しない。
公開LICENSE/依存manifestへのURLとハッシュもaudit JSONへ追加した。

## Phase 2 — 長期記憶

AIMemoryにoptional Semantic metadataと最大30世代の編集履歴を追加。旧データを
書き換えず読める。種類・主語・項目・値・出典・観測/更新/有効期間・状態・確度・
workspace・機微性・本人確認を保持。有効/更新候補/過去/矛盾/未確認/無効を区別。
同じ明示項目の異なる有効値は双方を矛盾として残す。自然文から勝手に事実抽出や
推測更新はしない。編集画面で項目と状態を確認する。機微指定は自動利用しない。
追加/編集/削除はSQLite保存成功後にモデルを変え、保存失敗を成功扱いにしない。

会話履歴にoptional AIEpisodeを保存。会話ID/日時/依頼/600字以内の抜粋要約/
人物/記録/資料/元メッセージ/workspace/provenanceを保持。抜粋は事実抽出ではなく
会話の引用。決定・未決フィールドは推測で埋めない。メモリOFFでは追加利用しない。
MemoryRetrievalOrchestratorは使い捨てSQLite FTS5/BM25+日本語2-gram、関連上位
最大5/8件、候補最大5000件。人物/workspaceを先に絞り、出典を再検証してから
文脈へ入れる。毎回freshな許可済候補を索引化するため削除/編集/失効の古いcacheを
再利用しない。RAGのProjectSearchIndexとは分離。明確な一致がなければ過去の件を
断定しない。cloudの過去エピソードも参照fingerprintを実行中の再検証へ渡す。

メモリ設定に検索・状態・種類・機微性・編集履歴・出典・更新日を追加。
backupにoptional aiMemoriesを加え旧backupで既存memoryを消さない。

検証: MemoryRetrievalChecks成功（旧codec、各状態、期限、機微、scope、日本語FTS5、
削除、2000件）。ホスト2000件約0.06秒、端末計測ではない。
既存next-generationチェック全成功。Debug preview成功:
2026-10-16T19-28-25-4dd2b054.log。途中のForm initializerエラーは修正済み。
旧履歴で検証可能な出典がないものはcloudへ再送しない。Embedding、抽象的な言い換えの
精度評価、巨大DBでの実機memory計測は未完了。

## Phase 3 — 人物メモリの表示

PersonConversationSummaryで許可されたローカル記録の抜粋を即時構成する。
人物詳細に概要、話してきたこと、直近記録に追加された決定、未解決事項、
会話タイムラインを表示し、全て会議IDで根拠へ移動できる。新しいカードや
外部AIの自動呼出は追加しない。毎回現在のrecordから組み立て、cacheを残さない。
参加者タグは参加の証拠であって各決定への合意の証拠とはしない。
最近の変化は決定の文字列差分のみで、変更の意味を推測しない。
旧タスクは担当personIDを持たないため、本人/自分の約束を同名の場合に自動断定
できない。関連タスクとして表示する。人物IDのないジャーナルは名前への言及であり
本人確定情報ではない。資料は元の会議から開く。PersonSummaryChecks成功。

## Phase 4 — Skills / Plugin UX

12の業務手順を独自記述し既存3件に追加。提案/経営報告/会議報告/企画/PowerPoint/
Word/会社書式/週月報/調査/メール/会議フォロー/人物要約。version/icon/scopes/costは
optionalで旧Skillを読める。bounded Markdown import/exportにも新metadataを追加。
宣言は実行権限を増やさず、registry/approval/record privacyを通る。

共通AIPluginIconを導入しGmail/Notion/calendar/Drive/GitHub/MCP/内蔵/Skill/recordを
区別。同じ定義を候補とチップに使用。ブランド素材はコピーせず既存MemoraIconの
機能symbolを使用（SF catalogでiOS18の範囲を確認）。外部画像URL取得はない。
候補を接続済み/内蔵/Skill/record/接続必要/未対応に分類。未接続もアイコンと理由を
残す。料金はモデル料金を無料/端末内と誤認させない。チップは情報表示と44pt削除を
分離しVoiceOverで状態/操作を明示。IME/native TextFieldとdraft ID処理は維持。
実行直前も選択pluginIDの有効状態を再確認し、切断/無効化を拒否する。

新規project/personの@候補はこの段階では表示しない。人物詳細のID固定経路を使う。
PluginIconChecks（6サービスの区別、fallback、15Skill、metadata往復）成功。
next-generation既存suite成功。Debug preview:
2026-10-16T19-30-09-6d4afb12.log 成功（既存警告1件）。
