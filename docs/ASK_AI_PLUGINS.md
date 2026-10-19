# Ask AI 空白ホームと @ 指定 — 2026-10-14

追加実装: カスタムスキルの作成・Markdown読み込み・編集・削除・共有、
ON/OFFと最終選択の確認。本文と選択履歴はSQLite、ON/OFFは設定に保存。
最大2スキルを組み合わせ、宣言したpermissionsで権限を付与しない。
MCPツールは名前・説明と依頼のローカル検索で選ぶ。
最新の設計・検証・未対応範囲は [NEXT_GENERATION_AI.md](NEXT_GENERATION_AI.md)。

## 実装

新規チャットの中央は空白。背景は MemoraPalette.background、1行ヘッダーはサイドバー／Memora（履歴・検索メニュー）／新しいチャット。アイドル時の挨拶とグローを外し、回答中のグロー・実際の状態表示を維持する。ライブラリとジャーナルの画面構成、3タブの既存順序、FABを変更しない。

既存の複数行 TextField を維持し、iOS 18 の TextSelection を追加した。UIKitの既存入力を読み取る observer は、delegateを取り替えず、コンポーザーの同じホスト・領域にある入力だけをフォーカス中に監視する。SecureFieldを読み取らず、フォーカスが外れたら監視状態を消す。未確定文字がある間は候補選択・送信を止め、IMEの確定を勝手に行わない。候補は確定後に開く。メールアドレス、URL、選択範囲を @ 検索と誤認しない。

候補パネルはコンポーザーの直上の通常サーフェス。候補数・Dynamic Type・画面内の余地に合わせて高さを制限し、内部スクロールする。選択済み対象は淡いモノトーンの行とアクセシビリティの選択状態で示す。キャンセル、外側タップ、@ の削除で閉じる。選択時にキーボードを閉じない。選択は `[@名称]` と削除ボタンで示す。本文の途中への挿入・編集をUTF-16範囲で追跡し、選択IDはSQLiteのDraftStoreに追加保存する。手入力の名称からIDや権限を推測しない。チャット履歴の保存形式は変更しない。

## レジストリ・実行・保護

- IntegrationCatalog が添付メニューの連携一覧と @ 候補に共通の名前・説明・別名・対応ツールを供給する。接続状態と無効化は同じ model.integrationState を参照する。
- 同梱MemoraSkill、AIToolRegistry、登録済みMCP設定、保存済み記録も候補になる。検索・表示・選択だけで外部APIへアクセスしない。画像生成など登録されていない機能は追加しない。
- IDは `service:…`、`skill:…`、`mcp:UUID`、`record:UUID`、`tool:…`。名前変更で実行先が変わらない。
- @ は明示指定。未指定の自然文は従来のルーティングとツール選択を維持する。指定時はモデルに提示するツールと実行時の両方にAIPluginExecutionPolicyを適用する。既存のWeb検索トグルも利用者の明示指定として併用でき、指定先から黙って除外しない。MCPの discovery も選択サーバーだけに制限する。
- ファイル指定だけなら、その記録以外の read_record は拒否する。Notion保存には送信を許可した記録のローカル検索・読み取りを前提ツールとして許可する。選択しただけで本文を取得・送信しない。グローバルの添付と@指定はツール対応BYOKで併用できる。明示指定のツール・記録制限、接続・料金・実行時の許可確認は維持する。非対応モデルや解析失敗では入力と添付を保持して理由を表示する。
- MCPIntegrationProvider、OAuth PKCE、Keychain、Schema検証、エンドポイント審査、フィンガープリント、1回答24回／1接続先1日50回の既存上限を再利用する。承認後にもレジストリ、ProviderのID、接続先・認証・料金・許可設定を再確認する。
- RecordAccessPolicyを維持する。Notionの保存前承認は送る記録と料金未確認を明示し、送信する関連タスクにも現在のプライバシー設定を適用する。
- Gmailの外部取得は料金未確認として承認を要求する。アカウント名と接続世代を確認し、承認後・認証更新中・取得中に接続が変わっていれば古い応答を利用しない。API上限などの一時的な認証エラーで有効な接続を解除せず、invalid_grantは再認証へ案内する。このGmail実アカウントの競合・再認証E2Eは未検証。自動処理では料金未確認のメール取得を拒否する。MCPは確認済み無料・審査済み読み取り・非公開文脈なしの条件だけ自動許可する。
- 拒否・実行失敗後の外部ツールの自動再試行を止める。HTTP 401／403／429などを認証・権限・上限の案内へ変換し、外部の生のエラー本文を表示しない。
- Composioは未構成のまま、既存の拒否動作を維持する。バックエンドのデプロイ、契約、運営者キーの追加はない。

## 対応状況

| 対象 | 表示 | 接続導線 | 実行経路 | この環境での確認 |
| --- | --- | --- | --- | --- |
| Gmail | あり | 既存OAuth設定 | 既存search_email/read_email＋承認 | OAuth Client ID未設定。接続ボタン無効を実機能として確認。実データ未取得 |
| Notion | あり | 既存トークン／親ページ設定 | 既存ページ作成＋承認 | 未設定表示と設定導線を確認。実接続・保存は未検証。Notionページ検索・閲覧は非対応 |
| MCP | あり | 既存登録・接続確認・OAuth設定 | MCPIntegrationProvider＋承認 | サーバー未登録を確認。モックProviderと実レジストリの境界検証。実サーバーE2E未検証 |
| 端末のカレンダー | あり | 既存EventKit権限 | 読み取り／承認付き登録 | 端末内エージェントの実読み取りをチャットと開発用完了ログで照合。登録は未検証。Google Calendar OAuthは追加していない |
| Memora内蔵スキル／検索／記録 | あり | スキル有効化設定 | 既存端末内／BYOKエージェント | 候補、選択、削除、ドラフト、ポリシー検証 |
| Web検索／Deep Research | あり | 既存Braveキー設定 | 既存承認付きBYOK経路 | キー未設定を表示。有料検索・調査は実行していない |
| Google Drive／GitHub | 利用不可として表示 | 実接続なし | 未構成Composioが拒否 | 未実装を利用可能として表示しない |

## 検証

`bash tools/checks/run-ask-ai-plugin-checks.sh` が以下10スイートをまとめて実行する。すべてローカルの実コード／固定fixtureで、外部通信・アカウント認証・有料実行なし。

1. ComposerMentionChecks：途中カーソル、日本語・絵文字、メール・URL誤認防止、marked text拒否、編集・ID復元、ツールと記録の制限。
2. PluginDispatchChecks：実レジストリからモックIntegrationProviderへ実行。指定外、Schema不正、別Provider ID、無効ツールがProviderへ届かない。
3. ToolIntegrationChecks：既存Schema・MCP namespace/fingerprint・SSE・未構成Composio拒否。無料確認・非公開文脈・fingerprint変更の承認条件を追加。
4. AIWebSearchIntentChecks。
5. AIConversationProvenanceChecks。
6. MCPOAuthChecks。
7. AIHistorySearchChecks。
8. AIJournalPrivacyChecks。
9. RootNavigationChecks。
10. RecordPrivacyChecks。

Simulator（iPhone 18 Pro Max）では、変更前と変更後の画面を観察。Light/Darkの空白ホーム、IME未確定の保持と確定後の候補、@G／@Notion／@MCP／@calendarの検索、選択と削除、キーボード維持、少数候補の高さ、内部スクロール、Gmail未構成拒否、Notion・MCP設定への導線、サイドバーを確認した。英語入力ではIME確定操作なしで@候補が開くこと、メールアドレスを誤認しないこと、途中カーソルの選択・削除で前後の本文が残ることを確認。accessibility_extra_largeで名前の折り返し・内部スクロール・キーボードとの非重複を確認。添付メニューの4項目とWeb検索トグルのオン／オフを確認した。最初の候補配置の重なりは検出後に修正し、コンポーザー直上へ収まることを再確認した。

検証中だけAI整理を端末内Foundation Modelsへ切り替え、通常送信・回答中の状態・会話表示を確認した。元のクラウド（OpenAI）・Auto設定へ戻したことを画面で確認し、今回追加した3履歴だけを削除した。元の履歴・記録は保持。検証用ドラフトをクリアし、文字サイズはlarge、外観はLight、キーボードは元の日本語かなへ戻した。

実Gmail／Notion／MCP／クラウドLLM／Brave、写真・一般ファイルの実インポート、録音・再生の実セッション、iOS 18実機、複数アカウントE2Eは未検証。録音・再生・インポートの実装は変更していない。VoiceOver用ラベル・操作名をアクセシビリティツリーで確認し、全VoiceOver操作の実機検証は未実施。

## 保護対象の差分

MemoraGlass、ProminentTabBar、ProminentTabItem、GlassSegmentedControl、GlassSegmentedPicker、MemoraMotion、ComposerBackdrop、CaptureMenuPopoverは差分なし。Glassの描画・サイズ・matchedGeometryEffect・navigationTransition・下部バー／FABの既存処理は変更なし。

AIComposerBarはTextSelection、入力observer、IME未確定中の送信停止のみ追加。QuickAIComposerは候補／指定削除の通常サーフェスoverlay、入力範囲処理、IDの送信、既存設定画面へのsheetを追加。既存Glassの配置、背景、展開・縮小、キーボード制御を書き換えていない。RootTabViewはAsk AIから既存サイドバーを開くためのclosureと許可条件のみ変更した。

## コスト

新たな固定費はない。新規の有料サービス契約、Composioバックエンド、デプロイ、運営者キーは追加していない。@ 候補検索は端末内だけで従量費なし。クラウドAI・Brave・外部サービスを利用者が実行すれば、その利用者のBYOK／サービス契約の従量費が発生し得る。料金不明の外部処理は実行前に承認を要求する。運営者が費用を肩代わりする新しい経路は追加していない。

## 最終確認の記録

- 10スイート成功。`git diff --check` 成功。
- コア実装の最終ビルド: `2026-10-14T08-28-50-afabef84.log`、成功。既存App Intentsメタデータ抽出警告1件、コンパイル／リンクエラーなし。Gmailは認証情報が残っていてもOAuth Client ID未設定なら利用不可とし、モデルにもツールを提示しない。
- Simulatorの端末内カレンダー実行は、同じチャットの回答と実処理完了ログ `MemoraPlugin: read_calendar completed` で確認。外部サービスを実行したように見せるモック結果はアプリに追加していない。
- Webトグル併用の指定集合・重複防止を含む10スイートとビルドを再確認済み。最終Simulatorで選択済み行の淡い強調とAXのselected属性、フォーカス監視の修正後の候補表示、外側タップ後の候補とキーボードの閉鎖を確認した。ライブラリへの移動後も未送信の本文と指定が保持された。最後の検証用ドラフトは消去した。
## スコープ付きの会話（2026-10-14）

プロジェクト／記録のBYOK読み取り会話も共通AgentConversationLoopを使用する。
公開するのは現在有効なsearch_records／read_record／list_tasksのみ。
グローバルAsk AIの@指定・スキル・MCP・承認経路は維持し、スコープ付き会話へ
外部プラグインや変更ツールを自動で持ち込まない。実registry・schema・現在の
所属／送信許可を毎回確認する。実接続のE2Eは未確認。
詳細と上限は[NEXT_GENERATION_AI.md](NEXT_GENERATION_AI.md)を参照。

## 2026-10-16: 記憶・成果物の拡張

Pluginは能力の単位、Toolは実行操作、Skillは手順、Memoryは継続情報、RAGは根拠検索、
Artifactは保存した成果物。Skillの宣言をアクセス許可として扱わない。

- 共通AIPluginIconを候補/チップで使う。ブランド画像の外部取得はない。
- 12業務Skillを追加。version/icon/scopes/costはoptional。旧Markdown/JSONも読める。
- 会社テンプレートは`template:<UUID>`。選択した項目名だけをAIへ渡し、ファイル本体は
  端末で適用。create_document/create_slidesのtemplate_id/template_fieldsを実行時検証。
- @の実ID・接続・無効化・料金・保存範囲を実行時に再検証。見た目の@文字は権限ではない。
- 人物詳細はID固定の専用会話を開く。person/projectの@候補だけを先に公開しない。
- Gmailはreadonlyのまま。Gmail Drafts APIは新しいOAuth同意を必要とし未接続。
- Deep Researchは取得済み根拠に応じて追加検索するが、最大6検索/16ソース/比較1回/
  120秒。回数・token上限は請求額保証ではない。中断/不足/不明日時を残す。
- 長期記憶は明示/承認のみ。Semanticと会話引用のEpisodeを分離し、FTS5/2-gramで
  関連候補を選ぶ。出典・許可・workspaceを再検証する。詳細は
  [実装と検証記録](ASK_AI_NEXT_IMPLEMENTATION.md) を参照。

## 2026-10-19: デザイン刷新とプロジェクト内の@指定

`AIPluginMenu` は@入力と＋の「プラグイン・スキル・ソース」で共通。
＋の操作は `ComposerActionMenu` に表示し、TextFieldを入れ替えずキーボードを維持する。
候補・チップへのタップは `ComposerFocusRegion` が外側タップ扱いから除外する。
メニュー全体を表示余地に制限し、アクセシビリティ文字サイズでは状態表示を縦積みにする。

個人のプロジェクトでは、`ProjectMentionSelection` が現在の所属・送信許可・registryの
利用可能／有効状態を検証する。公開するのは search_records / read_record / list_tasks と、
これらだけを使う「プロジェクトの要点整理」スキル、そのプロジェクト内の記録／ソース。
資料を明示選択した場合は検索・本文・タスク・履歴の根拠対象をその集合に限定する。
権限や所属が途中で変わった場合も回答を確定せず、理由を残して保留ターンを閉じる。

外部MCP・連携・書き込みスキルをプロジェクト内で使えるとは表示しない。
グローバルの権限・料金・MCPエンドポイント／fingerprint確認は従来の経路を維持する。
記録単体の@指定は未対応で、残った指定を黙って無視せず入力を保持して理由を示す。
プロジェクト専用ソースの指定を全体のAsk AIへ持ち越した場合も利用不可と表示し、
送信を実行せず入力・指定を保持して所属プロジェクトへの案内を示す。
検証の範囲と代表画像は [デザインレビュー](design-refresh/REVIEW.md) を参照。
