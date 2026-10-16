# Ask AI Next Generation 実装・検証記録

## Phase 0 — 基準 (2026-10-16)

`git fetch github main` / `git fetch origin main` 実施。開始SHAは
`af3007cbe73585e180c33982b206d1e9c846c408`。両remoteのmainとHEADが一致。
AGENTS.md / DESIGN.md / MCP.md / docs/NEXT_GENERATION_AI.md / 現行コードを照合。
DESIGN.md後半には旧4タブ、サンプルfallback、モデル選択UIの記述が残る。
現行AGENTS.mdと実装（Home / Library / Ask AI、実行不可は失敗表示）を優先する。

要求された35ファイルは現在のApp内に存在。既存Swift agent harness、有限予算、
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

## Phase 5 — 資料ファイルと企業書式

DOCXWriterはA4/見出し/編集可能な段落と表/日本語フォント指定を持つ実ファイルを生成。
既存PDF/PPTX/text共有にWordを追加。新規作成時もDOCX/PPTXを生成・ZIP/XML再読込
してからSQLiteの資料モデルとファイル参照を保存する。本文だけで完成扱いしない。
資料画面からQuick Look/保存/共有。Markdown編集後は古い生成ファイルを失効する。

CompanyTemplateは原本の別コピー・format・project/workspace・時点・version・brand・
解析情報・利用範囲を保持。資料のtoolbarから登録/構造確認/差し込み/preview/共有。
@候補にも実際に使えるテンプレートだけ表示。選んだ場合だけ項目名をAIへ渡し、
書式ファイル本体は端末内に保持。ツールのtemplate_id/fieldsを検証し承認後に適用。

差分エンジンは既存マスター/theme/layout/画像/notes/header/footer等の未変更partの
bytesを保ち、同じXML text要素内の{{name}}のみ置換。全欄の指定を要求し、分割欄・
外部参照・署名・macro・OLEを拒否。PPTX1欄120字/Word10000字、archive readerの
既存容量/CRC/path/XML上限を適用。ZIPは再構成するが未変更partは同一bytes。
再レイアウトや任意の既存文書の高忠実度編集ではない。文字あふれ/正確なページ数/
フォント代替の最終判定はQuick Look/Officeの確認が必要。完全再現とは表示しない。

テンプレートと生成ファイルを既存workspace backupへ含め、旧manifestはoptionalで
読み込む。資料更新/削除で不要な生成ファイルを除去。元テンプレートを上書きしない。
Python/Node runtime・新規server/worker/有料サービスはiOSへ追加していない。

検証: run-artifact-checks.shで実DOCX/PPTXを生成→再読込、表、日本語、長文、
escape、未変更master/styles/theme、分割欄/長すぎるPPTX/破損拒否を確認。
独立Python標準ライブラリOOXML差分PoCも両形式で成功。第三者エンジンをインストール
せず、未変更part同一性とXML packageを検証。python-docx/python-pptxを使う高度な
レンダリングPoC、Word/PowerPoint実アプリでの最終レイアウトは未検証。
Debug preview: 2026-10-16T19-38-12-ad5adfbb.log成功（既存警告1件）。

## Phase 6 — Deep Research / メール

ResearchLoopは本番とmockで同じ有限ループを使用。初期1〜3検索の結果から件数/
発行元/一次資料候補/日時の不足を判定し、元の話題から公式資料・最新発表・異なる
見解の検索を追加。Web本文の命令から検索語を作らない。最大6検索/16ソース/
比較モデル1回/120秒、入力context8000字/出力4096token。agent内の最終回答は
既存AgentRunBudgetの別上限も適用。これは請求額の強制上限ではない。

実際の検索開始/取得/不足判定/追加計画/モデル生成だけを記録。API抽出と全文閲覧は
区別。公開日が取得できないものは不明表示。公式ドメインは一次資料の「候補」で
検証済みと断定しない。引用番号の範囲を検証し、取得できた根拠だけをリンクにする。
不足が残れば未完了表示。失敗/中断の根拠を保持し自動再送しない。workspace変更/
キー変更/時間/停止で以後の処理を拒否。資料へ保存すると未完了状態と根拠URLを持つ
実DOCXを生成できる。数値の矛盾はモデルに比較を要求するが、機械的な事実検証や
網羅性を保証するものではない。

CloudAIServiceの比較生成だけopt-inの出力capを付け、途中のlength/max_tokensを
完成扱いにしない。未対応providerは失敗し、追加課金の自動fallback要求をしない。
[OpenAI公式API](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create) のmax_completion_tokens仕様を確認。

MailDraftをSQLiteへ保存（To/CC/BCC/件名/本文/時点/person/project/source/workspace/
状態）。approve後の保存成功を確認してネイティブ編集画面を開く。資料のtoolbarに
下書き一覧。編集/コピー/共有/Mailを明示操作で利用し、不明宛先は空欄。宛先の名前/
改行によるheader injectionを拒否。Mailを開いたことを送信済みと扱わない。
バックアップもoptionalで互換性を維持。

Gmailは現行gmail.readonlyのみ。公式の[drafts.create](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.drafts/create) はcompose/modify等が必要でreadonlyでは不可。
このビルドはOAuth Client ID未設定で、実接続を行っていない。追加scopeや送信APIは
導入せず、Gmail下書き保存は未接続のまま。アカウント/審査/本人の新しいOAuth同意を
含む別工程が必要。接続済みと表示しない。

検証: ResearchLoopChecksで本番ループの上限、重複、空、API失敗、途中結果、失効、
時間、保存失敗、replay、引用番号とMailDraft codec/不明宛先/改行拒否を確認。
run-memory-artifact-checks / run-next-generation-checks / run-motion-loading-checks /
run-optimization-checks は成功。実API/キー/実ユーザー記録はテストに使っていない。
Debug preview: 2026-10-16T19-45-30-e7dc3e92.log成功（既存警告1件）。

## Phase 7 — 統合・安全性の仕上げ

- 明示的な許可を持つproject fileをグローバルAgentのsearch_records/read_recordへ接続。
  project所属/選択ID/workspace/送信許可とmetadata fingerprintを読込後/次のmodel呼出前に
  再検証。個人以外/人物限定/常駐の自動読取へ流用しない。専用送信許可のない既存
  MemoraDocument本文は引き続きcloudへ自動送信しない。これらの会話は出典の全形式を
  永続検証できるまではcloudでの履歴再利用を拒否する。
- 作成資料に参照した会議/登録資料のIDと導線を残す。メール編集には既存DraftStoreを
  接続し、未保存の本文/件名/To/CC/BCCを復元。削除時にその下書きだけ片付ける。
- Semantic編集/矛盾判定を実テスト可能なAIMemory+Editingへ分離。最大30世代を保持。
  元の会話が残ればメモリ編集画面から開ける。保存失敗時は編集画面を閉じない。
- research queriesが6件になったbackupも復元可能にし、memory/draft/templateの
  件数・ID重複・参照名・内容上限を復元前に検証。履歴削除も保存成功後に反映。
- 現在のTeamBackendは記録サービス未接続。チームの新しいAsk AI/常駐処理へ個人の
  SQLite recordsを渡さない。ワークスペース変更は進行中の処理を止める。
- 人物taskの旧name照合は本人確定と表現しない。同名があるmergeで他人の担当を
  まとめて書き換えない。新しいpersonID付きtask移行は未実装。
- CompanyTemplatesの実画面で登録導線と未接続の説明を確認。Dark +
  accessibility_extra_largeでも内容が折り返され、操作できる。新規画面のtintは
  モノトーンへ統一。toolbar導線のVoiceOver操作名を補正。既存draftへの検査用末尾入力は
  取り除き、実record/認証/ファイルimport/送信は操作していない。

途中に追加したsource参照のprojectID optional対応漏れをDebug buildで検出し修正。
AgentSourceChecksのmock型も実型に合わせた。旧コードを無理なforce unwrapへ変えない。
現行の不明なsource所属を自動で別projectに割り当てない。

## 最終レポート A〜J

### A. 監査

開始main SHAと既存実装・旧文書との差分はPhase 0に記載。指定35ファイルは存在。
保存はSQLite、mediaはfile参照、資格情報はKeychainを維持。Cloud storage/MCP公開server/
Memora Intelligence/Team record backend/StoreKit等の未接続境界をサービス稼働と扱わない。

### B. 実装

Phase 1: 人物ID/候補/送信許可/会話の出典確認。
Phase 2: semantic/episode metadata・状態/履歴・FTS検索・編集/削除。
Phase 3: 根拠付き人物概要/話題/未決/時系列。
Phase 4: 12業務Skill・共通icon・チップ情報/削除の分離。
Phase 5: DOCX/実artifact保存・企業書式登録/差分適用/preview/backup。
Phase 6: 有限反復Research・引用/日時/不足・local mail drafts。
Phase 7: project file読取の実行前検証・編集draft復元・backupの上限/互換・統合確認。
各段階を別commitに分割。主要ファイル一覧は末尾。

### C. OSS

指定24repoのroot license/archived/push日時、LICENSE/依存manifest URLとhashをJSONへ記録。
Swift/SQLiteの独自実装を採用し、外部memory engine/framework/runtimeは採用しない。
MIT/Apache rootでも全component/推移依存を包括許諾とは扱わない。Anthropic等の素材を
コピーせず、Skillは独自記述。Carbone CE/外部worker/新規常時serverは未採用。
Aは実装、BはPython標準ライブラリでの独立差分PoC、Cは未導入。

### D. Memory / RAG

Working=snapshot、Episodic=履歴上のAIEpisode、Semantic=AIMemory metadata、
Procedural=MemoraSkill。MemoryとProjectSearchIndex/RAGは分離する。
FTS5/BM25/日本語2-gram、明示scope、時点、freshな権限/出典で候補を絞る。
状態・矛盾は本人の編集/明示項目で管理し、AIが雑談から勝手に事実を確定しない。
抽象的な言い換え、人物関係graph、on-device Embeddingは未評価/未実装。
過去の生成回答は根拠・内容・許可を確認できるものだけcloudへ再利用する。

### E. 人物

参加者タグを根拠に即時の抜粋summaryを構成。会議の決定と本人の発言を混同しない。
人物ID固定のAsk AI、記録IDの許可範囲、会議/元資料への導線を実装。
同姓/同名は自動確定しない。旧task/journalはname-basedのため本人の確定情報とは
扱わず、曖昧なら利用者の確認が必要。複数会議を跨ぐ意味的topic clusteringは未実装。

### F. 資料

標準PPTX/PDFを維持しDOCXを追加。実生成→ZIP/CRC/XML/Office本文の再読込→保存。
テンプレートはscalar markerのみ。既存master/style/theme/image/notesを保持する。
任意OOXMLの完全編集、複雑なrun分割、最終Officeレンダリングは対応保証しない。
Wordは基本見出し/段落/表の対応で、Markdown全書式の完全変換ではない。
生成PPTXは画像1枚ではなくtext box中心。標準PPTXのspeaker notes未出力は既存境界。

### G. Research / Email

有限反復の本番loopをmockで検証。API本文と抜粋、日付不明、未完了、引用番号を区別。
計画は端末の決定的な不足判定で、LLMによる無制限な再計画ではない。一次資料候補や
矛盾整理は独立した事実性保証ではない。費用上限はprovider側の請求設定とは別。
MailDraftは端末内保存/編集/コピー/共有/Mail。宛先不明は空欄。Gmailはreadonlyで、
Drafts APIは別OAuth同意・実アカウント検証を残す。送信APIは追加しない。

### H. Plugin / Skill

共通icon descriptorを候補/チップで共用。サービスごとの機能icon、未接続理由と料金、
独立した削除操作/VoiceOver label。15同梱Skill。手順は権限・コード実行能力ではない。
企業書式の@は実Toolへ接続。person/project @候補は未追加で、人物詳細/既存project経路を
使用する。端末AIで未対応のtoolや無効な必須toolは候補でも理由を示す。文字列@だけでは権限を与えない。

### I. 検証

架空fixture/mocksのみでhost suiteを実行。有料LLM/Brave/Gmail/MCP/Notionを呼んでいない。
MemoraはProject.json定義でXcode test targetを持たず、bitrig testの対象はないことを確認。
指定3runnerと追加runnerを使用。実device性能、token請求額、録音/Live Activity/Omi、
real-cloudの統合シナリオA〜E、実Mail送信/認証、Word/PowerPoint最終表示は未検証。
長い会話の実メモリ計測は未実施。2000件検索のhost測定は実機性能を意味しない。
@候補/チップの全操作と全画面のVoiceOver実機走査も未検証。根拠なしに全機能回帰完了と
主張しない。

### J. 残る改善点

- P0: 利用者の明示的なテスト用BYOK/モック接続で、端末のA〜E通し検証・権限変更中の
  UI/E2E・新旧backup実復元を確認。実機録音/Island/長い会話の性能を測定する。
- P0: TeamBackendの実record schema/認可を接続し、個人storeと物理的に分離する。
  それまではteam会話へ個人recordを流さない。
- P1: personID付きtask/journal関連、より自然なtopic要約、確認付きの構造化memory更新。
  document/source/外部メールを跨ぐ永続provenanceを拡張し、安全な履歴再利用率を上げる。
- P1: 会社書式のrun跨ぎmarker/表・画像差込、Office実レンダラーによるoverflow/ページ数確認。
  利用者管理のpython-docx/python-pptx workerで高度編集を別PoCとして検証する。
- P1: Gmail Drafts用OAuth同意/許可分離/再認証/E2E。実送信は常に本人の明示確認。
- P2: 日本語embedding/Hybrid rerankの測定、任意のproject/person @指定の権限連携、
  外部workerの認証/費用/保管条件、provider側の金額強制上限。


最終補正: 業務Skillのask_userはcloud側の共通harnessで提供し、端末内Skillの必須toolとは
しない。必要tool/無効状態/端末内モデルとの互換性を候補でも確認する。PowerPoint
テンプレートの@が端末AIで利用できない場合は、手動の端末内生成との違いを表示する。
会社書式artifactのWord/PPTX共有は保存済みファイルを一時コピーして渡す。標準writerで
原本の書式を作り直さない。コピーだけを片付け、保存済みファイルは残す。会社書式の
PDF変換は未対応表示にし、標準資料の既存PDFは維持。本文編集後は会社書式適用済み
という状態も失効させる。検証用の実生成ファイルを
[docs/fixtures/ask-ai-artifacts](fixtures/ask-ai-artifacts/README.md) に保持。

## 変更ファイル（レビュー用）

### Phase 0 — 99fddc9
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `docs/ASK_AI_OSS_AUDIT.json`

### Phase 1 — 17a22bd
- `App/AIConversationSnapshot.swift`
- `App/AIPluginExecutionPolicy.swift`
- `App/AgentTool.swift`
- `App/AskAIHeader.swift`
- `App/MemoraModel+AI.swift`
- `App/MemoraModel+AIProvenance.swift`
- `App/MemoraModel+Agent.swift`
- `App/MemoraModel+AgentTools.swift`
- `App/MemoraModel+AutomaticRecordTools.swift`
- `App/MemoraModel+Conversation.swift`
- `App/MemoraModel+Memory.swift`
- `App/MemoraModel+People.swift`
- `App/MemoraModel+PersonChat.swift`
- `App/MemoraModel.swift`
- `App/PersonDetailView.swift`
- `App/PersonIdentity.swift`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `docs/ASK_AI_OSS_AUDIT.json`
- `tools/checks/PersonIdentityChecks.swift`
- `tools/checks/run-next-generation-checks.sh`

### Phase 2 — f1f61ec
- `App/AIConversationEntry.swift`
- `App/AIEpisode.swift`
- `App/AIHistoryView.swift`
- `App/AIMemory.swift`
- `App/AIMemoryEditor.swift`
- `App/AIMemoryView.swift`
- `App/BackupPackage.swift`
- `App/MemoraModel+AI.swift`
- `App/MemoraModel+AIProvenance.swift`
- `App/MemoraModel+Agent.swift`
- `App/MemoraModel+Backup.swift`
- `App/MemoraModel+Memory.swift`
- `App/MemoryRetrievalItem.swift`
- `App/MemoryRetrievalOrchestrator.swift`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `tools/checks/MemoryRetrievalChecks.swift`
- `tools/checks/run-ask-ai-plugin-checks.sh`
- `tools/checks/run-tool-integration-checks.sh`

### Phase 3 — 89806b4
- `App/PersonConversationSummary.swift`
- `App/PersonDetailView.swift`
- `App/PersonMemory.swift`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `tools/checks/PersonSummaryChecks.swift`

### Phase 4 — d89168c
- `App/AIPlugin.swift`
- `App/AIPluginIcon.swift`
- `App/AIPluginIconView.swift`
- `App/AIPluginMenu.swift`
- `App/ComposerMentionStrip.swift`
- `App/MemoraModel+PluginExecution.swift`
- `App/MemoraModel+Plugins.swift`
- `App/MemoraSkill+Business.swift`
- `App/MemoraSkill.swift`
- `App/MemoraSkillMarkdown.swift`
- `App/SkillDetailView.swift`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `tools/checks/PluginIconChecks.swift`
- `tools/checks/run-next-generation-checks.sh`

### Phase 5 — 76e0fa6
- `App/AIPlugin.swift`
- `App/AIPluginExecutionPolicy.swift`
- `App/AIPluginIcon.swift`
- `App/AgentTool.swift`
- `App/BackupPackage.swift`
- `App/CompanyTemplate.swift`
- `App/CompanyTemplateDetailView.swift`
- `App/CompanyTemplateEngine.swift`
- `App/CompanyTemplatesView.swift`
- `App/DOCXWriter.swift`
- `App/DocumentDetailView.swift`
- `App/DocumentsView.swift`
- `App/MemoraDocument.swift`
- `App/MemoraModel+Agent.swift`
- `App/MemoraModel+AgentTools.swift`
- `App/MemoraModel+Backup.swift`
- `App/MemoraModel+CompanyTemplates.swift`
- `App/MemoraModel+DocumentArtifacts.swift`
- `App/MemoraModel+Documents.swift`
- `App/MemoraModel+PluginExecution.swift`
- `App/MemoraModel+Plugins.swift`
- `App/MemoraModel.swift`
- `App/OfficeArchiveReader.swift`
- `App/ProjectWorkspaceBackup.swift`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `tools/checks/DocumentArtifactChecks.swift`
- `tools/checks/office-template-poc.py`
- `tools/checks/run-artifact-checks.sh`

### Phase 6 — 6464a4e
- `App/AIHistoryView.swift`
- `App/AIPluginIconView.swift`
- `App/AgentTool.swift`
- `App/BackupPackage.swift`
- `App/CloudAIService.swift`
- `App/DocumentsView.swift`
- `App/MailDraft.swift`
- `App/MailDraftSheet.swift`
- `App/MailDraftsView.swift`
- `App/MemoraModel+AIProvenance.swift`
- `App/MemoraModel+AgentTools.swift`
- `App/MemoraModel+AgentWebResearch.swift`
- `App/MemoraModel+Backup.swift`
- `App/MemoraModel+Conversation.swift`
- `App/MemoraModel+MailDrafts.swift`
- `App/MemoraModel+ResearchArtifacts.swift`
- `App/MemoraModel+WebResearch.swift`
- `App/MemoraModel.swift`
- `App/ResearchLoop.swift`
- `App/ResearchPlan.swift`
- `App/WebResearchClient.swift`
- `App/WebResearchDetailView.swift`
- `App/WebResearchReport.swift`
- `App/WebResearchSource.swift`
- `App/WebResearchView.swift`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `tools/checks/ResearchLoopChecks.swift`
- `tools/checks/run-memory-artifact-checks.sh`

### Phase 7 — 統合補正・検証

- `App/AIChatMessage.swift`
- `App/AIMemory+Editing.swift`
- `App/AIMemory.swift`
- `App/AIMemoryEditor.swift`
- `App/AgentSourceReference.swift`
- `App/BackupPackage.swift`
- `App/CloudAIService.swift`
- `App/CompanyTemplateDetailView.swift`
- `App/CompanyTemplateEngine.swift`
- `App/CompanyTemplatesView.swift`
- `App/DocumentDetailView.swift`
- `App/DocumentsView.swift`
- `App/MailDraftSheet.swift`
- `App/MailDraftsView.swift`
- `App/MemoraDocument.swift`
- `App/MemoraModel+AI.swift`
- `App/MemoraModel+AIProvenance.swift`
- `App/MemoraModel+Agent.swift`
- `App/MemoraModel+AgentSources.swift`
- `App/MemoraModel+AgentTools.swift`
- `App/MemoraModel+AgentWebResearch.swift`
- `App/MemoraModel+AutomaticRecordTools.swift`
- `App/MemoraModel+Documents.swift`
- `App/MemoraModel+MailDrafts.swift`
- `App/MemoraModel+Memory.swift`
- `App/MemoraModel+People.swift`
- `App/MemoraModel+Plugins.swift`
- `App/MemoraModel+ProjectContext.swift`
- `App/MemoraModel+Residents.swift`
- `App/MemoraSkill+Business.swift`
- `App/MemoraSkill.swift`
- `App/PersonDetailView.swift`
- `DESIGN.md`
- `docs/ASK_AI_NEXT_IMPLEMENTATION.md`
- `docs/ASK_AI_PLUGINS.md`
- `docs/fixtures/ask-ai-artifacts/README.md`
- `docs/fixtures/ask-ai-artifacts/SHA256SUMS`
- `docs/fixtures/ask-ai-artifacts/generated.docx`
- `docs/fixtures/ask-ai-artifacts/generated.pptx`
- `docs/fixtures/ask-ai-artifacts/long.docx`
- `docs/fixtures/ask-ai-artifacts/poc.docx`
- `docs/fixtures/ask-ai-artifacts/poc.pptx`
- `tools/checks/AgentSourceChecks.swift`
- `tools/checks/MemoryRetrievalChecks.swift`
- `tools/checks/PluginIconChecks.swift`
- `tools/checks/run-memory-artifact-checks.sh`
- `tools/checks/run-next-generation-checks.sh`


## 最終検証結果

- Debug: `bitrig preview -platform iOS` 成功。
  `2026-10-16T20-09-12-062331f1.log`。
- Release: `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release` 成功。
  `2026-10-16T20-09-07-f1325244.log`。
- 両方とも既存AppIntents metadata抽出skip警告1件のみ。compile/link errorなし。
- 指定3runner＋run-memory-artifact-checks.sh成功。後者は本番loop/extensionとmockを
  使用し、same UUIDでも記録限定policyをproject fileへ流用できないことも確認。
- `git diff --check` 成功。Xcode test targetはProject.jsonに存在しない。
- 画面確認: 会社テンプレートの登録、モノトーン、Dark/巨大文字の折り返し、toolbar操作名、
  メール下書きの空状態。元のcomposer draftを保持。実recordの削除/編集やAPI呼出はない。
- [機械可読の検証記録](ASK_AI_NEXT_VALIDATION.json) に成功と未検証を分けて記録。
- [生成DOCX](fixtures/ask-ai-artifacts/generated.docx) /
  [生成PPTX](fixtures/ask-ai-artifacts/generated.pptx) と独立PoCの出力を保存。
  すべて架空データ。Officeでの最終レンダリングは未検証。

会社書式artifactのWord/PPTX共有は保存済みファイルの一時コピーを使い、標準writerで
書式を作り直さない。会社書式のPDF変換は未対応と明示し、標準資料のPDFを維持する。
新たなサーバー/課金設定/本番デプロイ/第三者コードのアプリ組込は行っていない。
本レポートの「実装済み」は外部サービスの実接続や実機での統合証明を意味しない。
