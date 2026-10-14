# Memora 品質改善 — 2026-10-14

## 最新mainの監査

`Skyjoy0512/Memora-iOS` main をfetchし、`a6deb20084f3f07372de3fd55bc20fc358c354d3`
とローカルmainが一致すること、作業ツリーが空であることを確認した。
AGENTS、NEXT_GENERATION_AI、IMPROVEMENT_BACKLOG、ASK_AI_PLUGINS、
AI_PLUGIN_MCP、PROJECT_WORKSPACE_V2、MONOCHROME_DESIGN、MAIN_NAVIGATION、
PERFORMANCE_OPTIMIZATIONと実コードを照合する。古い文書のタブ順ではなく
現コードのJournal / Library / Ask AIを基準にする。

| 領域 | 開始時の実装と確認範囲 | 残る境界 |
| --- | --- | --- |
| 会話 | 共通AIResponseText、実SSE、AgentConversationLoop、別々の保存履歴 | tab復帰で消去、global会話本体は非永続、project/recordのUIは別 |
| 操作 | globalの承認付き内蔵toolとBYOK/MCP | 添付はgroundedのみ、@と添付の併用をUIとmodel両方で拒否 |
| スコープ | ScopedAgent / RecordAgentのread-only loopと現在の権限検査 | project/recordの変更toolは未提供。実BYOKの往復E2E未確認 |
| Intelligent UI | bounded native8種類、Markdown fallback、承認付きタスク完了 | 候補編集/一括登録は未対応。JSON検証は数値の事実性を保証しない |
| ソース | PDF20ページ、画像OCR、UTF-8、YouTube公式oEmbed/thumbnail | 一般Web本文とOffice未対応。YouTube字幕/画像vision未対応 |
| 検索 | SQLite FTS5、Japanese2-gram、project派生索引、抜粋上限 | 正解資料付きRAG評価は未整備。ベクトルDBは追加していない |
| 連携/skills | native管理、明示@、ローカルランキング、Markdown手順 | Gmail/Notion/MCP/BYOK実認証E2E未確認。Drive/GitHub OAuth未実装 |
| iOS | Ask AI Widget、データWidget、6 Intents、録音Live Activity | App Group未設定。実データWidgetは未設定表示。AI Activity未実装 |
| 性能/保存 | 共通抽出、100msのstream公開、leaf、直列SQLite保存、backup旧版読取 | 今回の実機性能/実backup復元は未検証 |

「コードがある」「ローカルfixtureを通った」「Simulator操作済み」
「実機/実サービスで成功」を分けて記録する。外部認証情報やユーザーの記録を
検証fixtureへコピーしない。新しい有料契約、backend配備、ID変更は行わない。

## P0-1: 会話継続

- `didChangeTab`で会話を消す処理と、system linkからの暗黙のnew chatを除去。
  明示的なnew chatは従来どおりrequest ID、Task、承認/質問を取り消して空白にする。
- `AIConversationSnapshot`はworkspace別の追加SQLiteキー。履歴/record/mediaの
  旧形式は変更しない。新規インストールではresume documentがなく空白のまま。
- 600msの静かな区間にまとめて保存し、tab離脱/backgroundではcheckpoint。
  毎tokenの書込を避ける。背景でOSが即停止した場合の最後の未確定本文は保証しない。
  workspace切替だけは直列queueへ同期確定し、すぐ戻っても古いcopyを読まない。
- 最大2,000turn/8MiB（JSON escape分を保守的に見積もる）。超過は切捨てず
  保存失敗を表示する。完了済みexchangeの既存historyは引き続き保存する。
- 引用、engineの表示、完了したresident投稿を復元。未完了residentは投稿しない。
  中断した通常回答は未完了表示にし、自動再送せず、再試行の操作も復元しない。
- 生成UIの変更ID、tool policy、承認continuation、cloud sessionの許可集合は
  保存しない。復元した回答の再利用には既存provenance/現在のprivacy再検証が必要。
  このresume documentは実行履歴やbackup manifestの代替ではない。

検証: `AIConversationSnapshotChecks`は実codecと復元を呼び、引用/metadata/
resident、empty、別workspace、version/role/重複ID/容量、権限の非復元、中断の
安全表示を確認。既存21スイートを含む22スイートが成功。ネットワークを使わない。
最終Bitrig build `2026-10-14T19-35-26-cc04365c.log`成功（既存metadata警告1件）。
最初のprivate property参照エラーを修正して再buildした。iPhone 18 Pro Maxでは
既存履歴を送信せず再開し、Library往復で同じ会話が残ることを確認。
app switcherで終了→App Libraryから再起動→Ask AIで質問/回答/再送拒否の
表示を復元した。明示的なnew chatで空白と無効なnew-chatボタンへ戻った。
変更前/再開/復元/空白のスクリーンショットを観察。履歴・記録の追加削除、
有料推論、実外部アカウントの取得は行っていない。

## P0-2: 添付と操作・候補編集・共通表示（2026-10-15）

- globalのツール対応BYOKへPreparedAIAttachmentを渡す。既存の
  AIAttachmentText / ProjectSourceExtractionで一度解析し、同一ID/名前/URLの
  結果だけ再利用する。先頭8,000文字の未信頼JSONとして提示し、全文解析と
  誤認させない。ファイル本文はツール権限・承認・外部送信の許可にならない。
- @と添付の併用を許可するが、明示指定のツール/記録制限と現在の接続・料金・
  privacyは維持する。添付を含む回答のprovenanceは不完全とし、検証済みの
  履歴として再利用しない。無料のMCP読み取りでも個人情報を含む場合の承認を省かない。
- 解析の停止・失敗・モデル変更は未送信の入力と添付を保持。APIキー未設定も
  受理せず保持する。通信後の失敗は新しい入力がない場合だけ下書きへ復元する。
  ファイルはアプリ内の既存コピー、SQLiteにはファイル名だけを保存する。
  コピーが消えた場合は復元しない。添付の操作は対応BYOK限定であり、端末内AIの
  添付質問は従来のgrounded経路。外部操作の自動再送は追加していない。
- add_tasksの候補はJSON入力から厳密に検証し、30件まで。既存approvalカードに
  選択・タイトル・詳細・担当・期限の編集を接続。候補IDと記録IDを固定し、
  承認後にworkspace、保存保護、実ツールschema、現在のprivacyを再確認する。
  insertTasksのSQLite成功後だけ作成ID/実件数を表示する。完全一致の未完了タスクを
  二重登録せず、同じ回答内でのadd_tasks再実行も拒否する。外部サービスの
  idempotencyやserver課金保証ではない。
- AIUserMessageView、ConversationStatusLine、ConversationScrollFollowingを共用。
  Markdown / Intelligent UIは既存AIResponseTextを再利用。履歴・参照範囲・保存先は
  global/project/recordで分離したまま。キーボード・lazy rowのlayout変更を
  手動スクロールと区別し、過去を読む間は勝手に最下部へ戻さない。
  記録AIの質問カードと回答見出しを削減。プロジェクトの停止操作をtoolbarにも置く。
  コピー/共有/資料保存に生成UIのJSONを混ぜずMarkdownを用いる。
- Glassのshape、タブ、FAB、hero、safe area、capture/Omi、既存mediaは変更していない。
  QuickAIComposerの変更は添付の所有・準備・送信制御。旧resume snapshotへ追加する
  attachment/mentions/createdTaskIDsはoptionalで、旧履歴とbackup形式は維持する。

検証範囲:

| 状態 | 結果 |
| --- | --- |
| 自動チェック | 25スイート成功。添付identity/JSON/上限、mock loopと拒否、候補ID/記録ID/日付、scroll resize/手動閲覧、既存privacy/stream/MCPを含む |
| build | Bitrig `2026-10-15T07-29-50-dcc2965e.log`成功、後続のBitrig更新 `07-33-22-702cc526.log`も成功。既存AppIntents metadata警告。検証用コードのStorageKey参照エラーは修正済み |
| Simulator実操作 | iPhone 18 Pro Max。通常の承認/insertTasksで編集済み1件を保存しSQLite再読込一致、同一依頼再実行の拒否、選択ゼロで追加無効、拒否/停止で保存なしを確認。検証タスクのみIDで削除 |
| Simulator表示 | Light/Dark・accessibility_extra_largeで候補が折り返し、操作可能。選択のAX値on/offを確認。タイトルはTextField、詳細はTextEditorで入力確定後の値を実保存と照合 |
| 会話UI | 既存Hello履歴を再送せず再開。Library/プロジェクト往復で保持。新規Ask AIは空白。資料ゼロのプロジェクトは本文なしの理由を示し、質問を共通user bubbleから下書きへ戻せる。変更前後のスクリーンショットを観察 |
| 検証データ | 前回追加したQAbefore履歴1件と19:57作成の検証project threadを削除。元の記録/履歴/プロジェクトは保持。検証用draftをclear、外観Light/文字largeへ復帰 |
| コード・mockのみ | 添付→BYOK実モデル→実ツール選択、通信断後の添付draft復元、添付+実Gmail/Notion/MCP。今回の操作検証のモデル応答はfixtureで、実LLM E2Eではない |
| 未検証 | 実機、VoiceOverの読み上げ、Reduce Motionの実操作、長い実会話の負荷、backup実復元、全画面デザイン監査。性能改善率は計測していない |

新たな契約・backend・料金は追加していない。プロジェクト/記録の変更ツール、
添付由来の回答を次のcloud turnへ安全に継続するgrant、一般Web本文、Office本文、
正解資料付きRAG評価、実外部認証E2E、App Group/実機Widgetは残る。

## P0-3: 本文がない記録と復旧案内の区別（2026-10-15）

`Meeting.hasReadableAIContent`でタイトル・日時・状態だけの記録を本文と扱わない。
文字起こし/利用者のメモは処理状態に関係なく使い、要約/要点/決定事項/未決事項は
readyまたはpartialFailureのときに使う。録音直後・復旧直後の案内文がsummaryに
保存される既存仕様は変更しない。関連タスクや読める添付がない単一記録の質問は、
実モデルを呼ぶ前に本文未取得の理由を返す。privacy/workspaceの確認を先に通し、
入力は再送せず下書きへ戻す。タイトル/日時だけの質問も本文チェックを通るため、
その情報は元の記録画面で確認する必要がある。

検証中、失敗した復旧録音のsummaryに「文字起こしを開始できます」という案内文が
残っており、空文字チェックだけでは防げないことを確認した。状態を使う判定へ修正し、
同じ録音でAI回答/引用を作らず、理由とQARecordEmptyの下書きが表示されることを
Simulatorで確認。Light/Dark/大きい文字で観察した。修正前のQARecordCheckだけが
履歴に保存されていたため、その1件のみ削除した。元の録音・ノート・履歴は保持。

Bitrig `2026-10-15T07-50-41-aca6e3e8.log`成功、既存metadata警告1件。
ホスト25スイート成功に加え、アプリ内の新しいRecord AI readable evidenceが
「成功」であることを確認。保存したテキスト種別、空白、復旧案内を検査する。
検証後はクラウド（BYOK）/OpenAI/Auto、Light/large、LibraryのProjects選択に戻し、
Ask AIを空白にして入力をクリアした。追加費用・外部送信・識別子変更はない。

## 第三者の目線での再レビュー

- 新規Ask AIは空白でタブ往復後も会話を続けられる。入力と状態表示を共用したが、
  長い実会話の手動スクロール・キーボード往復は実機で未確認。
- 候補をその場で編集・承認し保存済みの結果へつながる。UIの編集だけで保存成功と
  表示しない。実モデルによるPDFの候補抽出/ツール選択のE2Eは未確認であり、
  添付からの実用性全体は完成扱いしない。
- プロジェクトはチャットと資料の関係がまだ弱く、本文未取得の理由は会話時に
  初めて分かる。AI参照可否と資料追加後の解析状態が次の優先。
- 自動選択は現行ローカルランキングを維持。日本語の評価セットと実認証サービスを
  使った選択/実行の精度は未確認。
- Intelligent UIの候補編集/登録は実保存経路で有用性を確認。比較/グラフの数値の
  正しさまでJSON検証は保証しないため、根拠データの評価が残る。
- 全画面のVoiceOver/Reduce Motion、backup実復元、App Group/実機Widget、
  実機Release性能は未実施。Widget/録音Activityと識別子に変更はない。

## 次の実装順

1. ソース状態とOffice、一般Webの安全な取得、正解付きRAG評価。
2. 添付からのBYOK実E2E（利用者の安全なテスト環境が必要）。
3. 連携/skillの評価、全画面のappearance/accessibility、backup実復元、
   Apple識別子/App Group準備、実機性能と実サービスE2E。

現時点でプロジェクト全体の完成とは扱わない。
