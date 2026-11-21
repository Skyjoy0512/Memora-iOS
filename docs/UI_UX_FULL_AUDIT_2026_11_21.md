# Memora 全画面 UI/UX 点検

点検時の対象は `3e9adc13` のiPhone版。主要画面、下層、編集シート、権限・失敗・空の状態、条件付き機能を調べた。優先度は、P0がデータ保護、P1が日常操作・状態表示の誤解、P2が読みやすさ・発見しやすさ。後続の修正は「実装結果」に記載。

## 点検範囲と根拠

- `App` のSwift 1,386ファイルを走査し、Viewを含む455ファイル、名称上の画面・シート候補255ファイル、ナビゲーションタイトルを持つ191ファイルを抽出。候補には行部品・表示例が含まれ、名称規則から外れるページもある。ルート定義19ケース、設定12カテゴリ、各領域のリンク・シートを照合した。末尾に画面・シート候補の索引を掲載。
- iOS 27.2のiPhone 18 Pro Maxプレビューで、サイドメニュー7行き先、設定トップと12カテゴリ、録音メニュー、ノート作成シート、プロジェクト一覧、プロジェクトの記録・チャット・参考資料、レコーダーハブを確認。合計27画面・タブ・シート。設定のAI／録音は最大文字サイズでも目視した。設定下層や条件付き画面の大半はソース点検。画面遷移後にアクセシビリティツリーの取得が連続して失敗した箇所はスクリーンショットで補った。
- `ai-design-check` 0.16.3は `App Shared` にエラー23件、警告145件、備考1件。指摘は88ファイルに分布。余白116件、固定文字14件、文体13件、角丸9件などを含む。固定文字14件は画像書き出しのレイアウト。組み込みHTMLの検出にもライブラリ内部文字列やアプリ側で上書きするスタイルが含まれる。別のリポジトリ内検査は既定Listスタイルを9ファイルで検出したため、公開画面／診断例／意図的な選択リストに分けて確認する。
- 実機、VoiceOverの実際の読み上げ、iOS 26、外部接続・録音・バックアップ復元の実操作は今回の未検証範囲。見た目と操作が関係する項目は、下表の「再現・確認条件」で実装時に検証する。

## 優先候補

| ID | 優先度 | 現状と根拠 | 改善案と完了条件 |
| --- | --- | --- | --- |
| U01 | P0・Debug限定 | 診断の「デモデータを入れ直す」はボタンから直接、記録・プロジェクト等の置き換えを呼ぶ。通常利用データを持つプレビューでも入口が見える。操作は未実行。 [設定](../App/SettingsCategoryView.swift#L515)・[処理](../App/MemoraModel+Samples.swift#L4) | 変更対象と件数の確認を挟むか、隔離されたデモデータで開く。非破壊の「サンプルを追加」とセクションを分け、キャンセルで全データが残ることを検証する。 |
| U02 | P1 | ライブラリの長さソートは全記録を並べ替えた後、日付ごとに再結合する。例として今日60分、昨日50分、今日5分は画面で60→5→50分になり得る。 [並べ替え](../App/LibraryView.swift#L717) | 長さ順のときは全体を長さでそろえる。日付区分を維持する仕様なら選択名に「日付ごと」を明記する。異なる日付の3件で確認する。 |
| U03 | P1 | Ask AI内のモデルシートでは登録モデルを直接選べる。設定のモデル選択には、APIキーがないモデルを無効化する判定がある。 [チャット](../App/AIChatModelSheet.swift#L10)・[設定](../App/AISettingsView.swift#L35) | 両方で同じ利用可否と理由を表示する。「選べない→キー設定→選べる」まで確認し、質問の下書きを保持する。 |
| U04 | P1 | 設定の「最近削除した項目」の件数は記録だけ。遷移先ではジャーナルも表示するため、ジャーナルだけ削除したとき入口は「なし」になる。 [設定](../App/SettingsCategoryView.swift#L418)・[削除一覧](../App/RecentlyDeletedView.swift#L20) | 入口の件数を両コレクションと一致させる。ジャーナルのみ、混在、復元直後の3状態を検証する。 |
| U05 | P1 | カレンダー選択は未選択なら全件を表示する仕様だが、未選択時に個々の行を「非表示」と読み上げる。 [カレンダー選択](../App/CalendarSelectionView.swift#L19) | 「すべて」を明示するか、実効状態に合わせて行を表示・読み上げする。未選択、1件選択、最後の1件解除で実際のジャーナルと一致させる。 |
| U06 | P1 | 録音中の「一時停止」「終了して保存」は横並び・各1行固定。最大文字サイズではシートは全高になるが、ボタンは横並びのまま。文言の詰まりはソースからの候補で、録音中は未実測。 [録音中の操作](../App/CaptureSessionView.swift#L154) | 幅・文字サイズに応じてボタンを縦に並べ、終了・保存の全文を表示する。キーボードあり、一時停止、保存中、失敗、バックグラウンド復帰を実機で確認する。 |
| U07 | P1 | 新規ノートの見出しとタイトル欄が同じ「新しいノート」。本文案内は画面上で薄く、資料追加は高さ360ptの編集欄の下にある。 [入力欄](../App/ProjectSourceAddSheet.swift#L119) | 「タイトル（任意）」など役割を示すラベルと、読みやすい色を使う。編集欄の高さを画面に合わせ、添付と保存の行き先を入力中も確かめられるようにする。 |
| U08 | P1 | 設定のヘルプ・プライバシーポリシーは「準備中」の表示行。アカウント・データ保護の質問からたどれる案内がない。 [ヘルプと情報](../App/SettingsCategoryView.swift#L434) | 利用できるヘルプとポリシーの入口を用意し、端末内保存・外部送信・削除の問い合わせ先へたどれるようにする。公開前に双方のリンクを確認する。 |
| U09 | P1 | チーム未接続でも作成・参加フォームを開ける。チーム名や招待コードを入れた後でバックエンドが未接続だと分かる。 [入口](../App/WorkspaceSwitcher.swift#L18)・[作成](../App/TeamCreateSheet.swift#L15)・[未接続実装](../App/UnconfiguredTeamBackend.swift#L5) | 入口で接続可否と理由を示す。作成のプラン条件と参加の招待コード条件を分け、入力を求めるのは実行可能な場合にする。 |
| U10 | P2 | タスクの担当者は読み上げ文と編集にある一方、通常のタスク行では表示しない。 [タスク行](../App/TaskRow.swift#L49) | 担当があるものだけ短く表示し、期限・取り組む日と区別する。担当なしの行の密度を保ち、長い名前は拡大時に折り返す。 |
| U11 | P2 | プロジェクトの参考資料タブには上部の紙クリップ、下部のAsk AI添付、下部の作成＋が同時にある。空状態では見出しとボタンが同じ「参考資料を追加」。実画面で確認。 [プロジェクト](../App/SpaceDetailView.swift)・[参考資料](../App/ProjectSourcesView.swift) | 既存の操作を「このプロジェクトに保存」「この質問に添付」「新規作成」と文言で区別する。空状態の見出しは状態、ボタンは操作を書く。 |
| U12 | P2 | 参考資料の本文検索は非同期で、会議の一致があるときは本文検索完了前に件数を表示し得る。 [ライブラリ検索](../App/LibraryView.swift#L302) | 先に出せる結果は表示しつつ「参考資料を検索中」を併記する。確定件数は本文検索完了後に表示し、古い検索の件数を混ぜない。 |
| U13 | P2 | Web調査のキー未設定案内が「設定 › AI整理 › Web検索」を示す。現行の画面名は「AIと要約 › AIモデル › 詳細設定 › Web検索・調査」。 [調査](../App/WebResearchView.swift#L28)・[設定](../App/AISettingsView.swift#L96) | 現行の文言に合わせ、調査の画面からキー設定へ直接開ける導線を置く。既存の送信先表示とコスト確認は同じ操作で確認する。 |
| U14 | P2 | 設定の録音ページでは文字起こしエンジンと日本語を一行の補足文字列で表示する。最大文字サイズでモデル名の途中で不自然に折り返された。 [録音設定](../App/SettingsCategoryView.swift#L263) | エンジンと認識言語を個別の値として縦に表示できるようにする。値が長い場合も項目名と対応が分かることを確認する。 |
| U15 | P2 | 外部レコーダーハブではOmiは機種名を直接表示するが、PLAUDは「他のレコーダー・ボイスメモ」の補足にのみ登場する。実画面で確認。 [入口](../App/RecorderStatusToolbarButton.swift)・[音声取り込み](../App/RecorderAudioImportView.swift) | 「直接接続」と「音声ファイルを取り込む」を分け、PLAUDの取り込み経路を明記する。未接続のときに接続・再接続・取り込みの選択違いが起こらないか確認する。 |
| U16 | P2 | バックアップ中のオーバーレイは画面を覆うが、進捗の読み上げ用モーダル指定がない。保存容量・復元失敗・キャンセルの体験は未操作。 [処理中表示](../App/SettingsBackupView.swift#L70) | VoiceOverのフォーカスを現在の処理状態へ移す。処理が測定できるときだけ進捗を出し、待機中と処理完了、失敗後の次の操作を確かめる。 |

## 領域別の改善候補と残る確認

表の「実画面」は今回表示した範囲。行中の下層・権限・状態はソース点検と再現候補を含む。

| 領域 | 対象ページ・状態 | 次に確かめること／改善案 |
| --- | --- | --- |
| 初回体験・保護 | オンボーディング各ステップ、用途選択、初回サンプル、ロック画面 | スキップ・端末だけで始める・録音を始めるの違いを先に理解できるか。マイク拒否やFace ID失敗時に戻れるかを、空のテスト端末で通す。 |
| 共通ナビゲーション | サイドメニュー、検索、深い画面へのリンク、ワークスペース | 実画面は7行き先を確認。検索の対象と現在位置を読み上げで一意にする。ワークスペース切り替えは現行では設定内にあるため、チームが使える状態で切り替えと選択中表示の見つけやすさを確認する。 |
| ライブラリ・ファイル | 一覧、絞り込み・並べ替え、検索、選択・一括移動／共有／削除、全記録 | 実画面で通常一覧を確認。U02・U12。絞り込み中に元の一覧へ戻る操作、複数選択時に対象件数・対象種類・実行結果が一致することを確認する。 |
| 記録の詳細 | 要約・文字起こし・ノート、再生、参加者、話者名、マーカー、名前変更、抽出情報 | 録音なし／読み上げ中／一部失敗の状態で、再生・再試行・出典の違いが伝わるか。長文の切り替えは前回の回帰確認済み。次は時刻リンクから開いた直後の選択行・同じ記録への復帰を確認。 |
| 要約と復旧 | 未処理、処理中、失敗、部分成功、要約生成、履歴と差分、抽出・根拠編集 | 失敗した工程と残った音声・本文を一緒に表示する。同じ記録の「初回要約」「再生成」「過去版の復元」で上書き範囲を誤認しないことを確認。 |
| 録音・取り込み | 作成メニュー、録音中・停止・保存、オンライン会議、外部ハブ、Omi／PLAUD、ファイル選択 | 実画面はメニューとハブ。U06・U15。実機で許可拒否、割り込み、保存失敗、終了後の復旧を確認する。 |
| プロジェクト一覧と詳細 | 一覧、作成・名前変更、ワークスペースの記録／チャット／参考資料、添付と関連タスク | 実画面は一覧と3セクション。U11。共有・個人、長い名前、空のチャット、資料読み取り中の操作可否が迷わず分かることを確認する。 |
| 参考資料 | 追加・編集・添付選択、URL、PDF／分割、画像OCR、音声・字幕、原文・要約、プライバシー | 実画面は新規ノート。U07。追加された資料がノートとは別に保存済みである点を、閉じる前に認識できるか。PDF・動画・空のURL・失敗時は次の操作をエラー箇所の近くに置く。 |
| ジャーナル | 日付・タイムライン、イベント／メモ／写真／移動、追加・編集、振り返り・週報、予定・地図・ヘルスケア | 実画面はルート。予定を表示する日と実際の保存対象を区別する。昨日と今日、同日複数件、許可なし、環境変更後に、追加時刻と保存先が意図どおりか確認する。 |
| Ask AI | ホーム、履歴と検索、新規チャット、入力・添付・メンション、モデル、音声入力 | 実画面はルート。U03。選択中のモデル・外部検索・添付と、実際に次回の送信で使われる範囲の一致を確認する。検索入力停止は前回修正済み。 |
| Ask AIの回答と承認 | 処理中、出典、読み上げ、回答アクション、生成UI、承認・質問・拒否、下書き回復 | 「内容の確認」「権限の承認」「実際の完了」を読み上げと見た目で区別する。生成フォームは修正後の入力／選択／承認ダイアログをiPhone上のVoiceOverで確認する。 |
| マーケットプレイス | ホーム、スキル／要約テンプレート／コネクタ、利用中、追加・編集・詳細、コミュニティ | 実画面はルート。カテゴリに絞られているかを検索結果でも分かるようにする。「追加済み」「接続済み」「Ask AIで利用可能」を同じ状態名称で表示し、設定と見比べる。コミュニティの本番接続は条件付きで確認する。 |
| タスク | 一覧・フィルター、作成・編集・期限・担当、関連タスクと元記録、チームボード | 実画面は一覧。U10。期限・今日取り組む・相手待ちを比較し、絞り込み中の解除と対象件数が伝わること、元記録削除後の案内を確認。 |
| 資料・メール | 資料一覧・検索・詳細、編集と版管理、スライド、PDF／Word／PPTX、会社テンプレート、メール下書き | 実画面は資料一覧。編集前の書き出しを選ぶ場面で、版・書式・最新の編集状況を確認できるようにする。PDF中止、出力失敗、長文・極端に長いスライド名は再現用データで確認。 |
| 人物 | 一覧、詳細、確認済み・未確認の発言、人の追加・編集・削除 | 実画面は一覧。未確認の同姓・省略名を紐付け済みの記録と誤認しないか。人物を削除した場合に残る記録と関連付けの説明を確認。 |
| 調査 | Web調査、結果・出典、プロジェクト保存、履歴・削除 | U13。送信前に検索語・サービス・料金を把握できることと、調査履歴を削除しても保存済み資料が見つかることを確認。 |
| 共有・チーム | ワークスペース選択、招待・作成、チーム共有の一覧、共有プロジェクト／記録、共有シート | U09。外部接続状態をテスト環境で確認し、閲覧専用、所有者、音声を含む範囲の表示を一貫させる。 |
| OS上の入口 | ウィジェット、録音Live Activity、コントロール、ショートカット、通知、共有拡張 | ソースと入口を確認。通常のアプリが閉じているときも、録音の実状態とリンク先が一致するかを実機でテスト。通知拒否・削除済み・保護中のリンクも対象。 |

## 設定12カテゴリの下層点検

12カテゴリの入口はすべてプレビューで開いた。下表は子画面と確認する状態。

| カテゴリ | 子画面・状態 | 改善候補 |
| --- | --- | --- |
| アカウント | プロフィール、写真・ミー文字、認証、メール、サインアウト／削除 | ローカル利用と未接続を入口で区別し、外観の変更とサインインの場所を明確にする。 |
| ワークスペース | 選択、チーム作成・参加、招待コード | U09。選択中の範囲と個人データの保存先を表示する。 |
| プランと利用状況 | プラン、クレジット、法人ライセンス、チーム共有 | 設定上の割当とサーバーから取得した残高を明確に区別する。購入未接続時に端末設定であることが一覧から分かるかを確認。 |
| 録音と文字起こし | エンジン・言語、認識キー、用語集、Gmail由来候補、声、話者識別、外部デバイス | U14・U15。未接続、キー未設定、モデル未取得のどれが足りないかを同じ位置で示す。 |
| AIと要約 | 登録モデル、プロバイダー・キー、モデル上限、Web検索、要約スタイル／テンプレート、スキル、メモリ・常駐エージェント | U03・U13。現在使われる設定を先頭に置き、上書き条件と利用停止理由の表示を統一する。 |
| ジャーナル | 自動記録、除外場所、カレンダー選択、権限拒否 | U05。権限を許可しなかった場合、押したスイッチ横に必要な設定と再開手順を表示する。 |
| 連携 | Gmail、Notion、MCPとプリセット、Webhook、iOS統合、未接続サービス | 接続済みでもAsk AIをオフにできるため、接続と利用許可の表示を同じ用語でそろえる。未設定時は接続に必要な項目の近くへ案内。 |
| 表示と操作 | システム／ライト／ダーク、触覚 | 変更直後のガラス、ボタン、プレースホルダーを確認。高コントラスト、透明度を下げる設定、視差効果を減らす場合も対象。 |
| プライバシー | Face ID、保存先、記録・資料ごとの外部送信 | 端末全体の保護と、個々の記録の送信許可の違いを、設定と詳細の両方で伝える。 |
| データ管理 | 保存容量、クラウド保管、下書き回復、バックアップ、共有受信箱、ごみ箱 | U04・U16。復元可否、進行中、完了、キャンセル、書き出し一時ファイルの扱いを隔離端末で確認。 |
| ヘルプと情報 | 設定について、ヘルプ、プライバシーポリシー、Open Source、バージョン | U08。ライセンスは設定トップにも入口があるため、ヘルプ内から探す場合の見つけ方も確認。 |
| 診断とプレビュー | 音声計測、状態ギャラリー、表示例、サンプル追加、Debugの再設定・計測 | U01。閲覧だけの画面、架空データを追加する画面、既存データを変える画面を明確に分ける。 |

## 実装結果

- **U01〜U05・U09** デモデータの置き換え前に対象と件数を確認し、キャンセルできるようにした。ライブラリの長さ順、ごみ箱の合計件数、カレンダーの全件表示と読み上げをそろえた。APIキー未設定のモデルと、未接続のチームは選択前に理由を表示する。
- **U06〜U08・U10〜U16** 大きな文字サイズ向けの録音ボタン、ノートのタイトルと添付、タスクの担当、プロジェクトの参考資料、検索中の表示、Brave Searchの設定導線、文字起こし、外部レコーダー、バックアップ中の読み上げを改善した。ヘルプとデータ保存・外部送信の説明をアプリ内から開けるようにした。
- **追加修正** Ask AI履歴の空表示、プロジェクト移動の説明、端末内で利用を始めるボタン、プラン設定の保存表示、グラフの数値一覧、資料の版履歴、声の登録案内を見直した。
- **確認済み** iOS 27.2のシミュレータでデモ置き換えのキャンセル、個人ワークスペースの選択、設定から連携画面への移動、ツールバー検索、録音メニュー、異なる日付の記録をまたぐ長さ順を確認した。ノートは保存と再起動後の表示、最大文字サイズで入力例が収まり「次へ」で本文に移れることを確認した。
- **残る確認** 公開用プライバシーポリシーと問い合わせ先の登録、実機のVoiceOver・録音中断・バックアップ復元、外部サービス接続後の操作確認。

### マーケットプレイス・人物・資料の追加対応

- **マーケットプレイス** 0件の画面で検索範囲を表示し、入力した検索語のまま全カテゴリに広げられるようにした。コネクタの接続状態を一覧と詳細でそろえ、詳細ではAsk AIでの利用状態も別の行に表示する。
- **人物** 名前だけが一致したタスクとジャーナルの見出しを具体化した。人物を削除する前に、参加者の関連付けが外れることと、記録・タスク・ジャーナルの内容は残ることを表示する。
- **資料** 編集前の会社ファイルを開く・共有する操作と、最新内容のテキスト共有を区別した。PDFの進捗を表示するとき、読み上げフォーカスを進捗見出しに移す。
- **確認済み** iPhoneシミュレータで検索範囲の切り替え、設定側の未接続表示、人物削除の確認・キャンセル・確定、長文PDFの進捗・プレビュー・キャンセル、架空の会社ファイルの共有案内を確認した。実機のVoiceOverと、接続済みの外部サービスは別途確認が必要。

### Ask AIの添付・モデル選択・コネクタ

- **添付** カメラ・写真・ファイルをコンパクトに並べ、最近の写真とWeb検索を下に置く。
- **モデル選択** 行間に共通の余白を使い、現在のモデルをチェックで示す。
- **コネクタ** 紹介文と装飾を削り、接続状態別にサービスを表示する。カスタムコネクタとWebhookは準備中のサービスより先に置く。
- **点検** `ai-design-check` 0.16.3の対象3画面の指摘は7件から0件。アプリ全体では既存のエラー21件、警告136件、備考1件が残る。
- **検証** iPhoneシミュレータのE2E 2件で添付・モデル選択と下書きの復帰を確認。Bitrigでコネクタの未接続表示、Gmailの設定要件、MCP・Webhook設定への遷移を確認した。外部サービスの認証は未実施。

## 追加点検 2026-11-22

`8fa5cdcf` から、ライブラリの右スワイプ選択と、前回の監査以降に変わった導線を点検した。1,387 Swiftファイル、456 View定義ファイル、画面・シート候補255件を走査。255件はすべて末尾の索引にあり、索引には名称規則に当てはまらない補助画面・部品も13件ある。現行のライブラリ系20ルートと設定12カテゴリを、3タブ、サイドメニュー、各画面の子画面・シートと照合した。

### 新しく確認した改善点

| 優先度 | 画面と確認条件 | 現状と改善案 |
| --- | --- | --- |
| P1・修正済み | ライブラリ › コンパクト › 長いタイトルの行を深く右スワイプ | 修正前のiPhone 18 Pro Maxで、選択直後の行が90ptから94ptに変化した。高さをそろえた後も、一覧上部の操作列とサンプル案内が消えるタイミングで、スワイプ中の行末が日付見出しに重なることを録画で確認。選択マークの領域を先に確保し、選択中は周囲の表示を保ったまま対象外の操作を無効にした。 [ファイル一覧](../App/LibraryView.swift) · [行の実装](../App/ProjectRecordRow.swift) · [E2E](../tests/library-selection-layout.e2e.ts) |
| P1 | ライブラリ › 検索結果 › 記録を右スワイプして選択 | 選択開始と同時にクエリが消え、一覧が通常の候補に切り替わる。検索結果で複数件を選ぶ場面を確認し、選択中の対象範囲と解除後の検索位置を保ちたい。ソースで確認。 [検索と選択](../App/LibraryView.swift) |
| P1 | ライブラリ › 一括選択 › 移動 | 全プロジェクトの記録を表示するライブラリからも「移動元の一覧から非表示」と案内する。移動で変わるのはプロジェクトへの所属。説明を件数と移動先に絞り、ライブラリとプロジェクトの両方で移動後の見え方を確認する。ソースで確認。 [移動シート](../App/BulkSpacePickerSheet.swift) · [保存処理](../App/MemoraModel+Spaces.swift) |
| P2 | プロジェクト一覧 › チャット履歴 › 存在しない名前を検索 | 履歴が存在しても「チャットはまだありません」と表示する。履歴が空の場合と検索結果ゼロを区別し、検索をやり直せるようにする。ソースで確認。 [チャット履歴](../App/ProjectChatsView.swift) |
| P2 | タスク編集 › 元の会議 › 記録0件 | 「なし」だけが表示される。既存リンクの解除操作と、リンクできる記録がない状態を区別する。ソースで確認。 [元の会議ピッカー](../App/TaskMeetingPicker.swift) |
| P2 | ノート詳細 › 資料を添付 › 同じ保存先に未添付の資料が0件 | 「添付できる資料がありません」から、同じ保存先にある資料が対象だと分からない。どこに資料を追加すれば選べるかを空状態で示す。ソースで確認。 [資料添付](../App/ProjectNoteAttachSheet.swift) |
| P2 | マーケットプレイス › コミュニティに投稿 › 自作品0件 | 作成を促す文があり、選択画面から既存エディターへ行けない。投稿サービスが使える環境で、空状態からスキル・テンプレートの作成へ進めるようにする。ソースで確認。 [投稿項目の選択](../App/CommunitySubmissionPicker.swift) · [既存の作成入口](../App/MarketplaceCreationMenu.swift) |
| P2 | 資料 › スライド編集 › 資料名を消す | セクション名と空欄のプレースホルダーが同じ「資料名」。ラベルを残し、同じ語の重複を減らす。unslop-ui U7に該当。ソースで確認。 [スライド編集](../App/PresentationEditorView.swift) |

### 検出結果と確認待ち

- BitrigでiOSのビルドとプレビュー起動が成功。選択E2EはiPhone 17eとiPhone 18 Pro Maxで成功した。短く右スワイプして「選択」、深く右スワイプして即時選択、メニューからの選択、複数選択と解除を通し、行の上下位置・高さと隣接行の境界を比較。コンパクト表示のスワイプ録画をコマ送りし、対象行が直下の日付見出しに重ならないことも確認した。
- iOS 27.2の主要画面E2Eは6ケース成功。3タブ・下部入力欄、ライブラリ検索、下層の資料と表示例、設定のAI／録音／プラン／接続、プロジェクトの3タブ、ダーク表示のジャーナルとプロジェクトを確認した。プロジェクト切り替えはテスト側で表示の準備を待つようにして再実行した。
- [ai-design-check](https://github.com/enmerasoftware/ai-design-check) 0.16.3の全体走査は修正前後ともエラー21件、警告136件、備考1件。余白107件は既定グリッドとの差で、6ptなど既存トークンに合う値を含む。固定文字14件は要約図版のキャンバスと表示パネル。正式名称のAsk AI・Google Meet・Face IDは表記を保持。組み込みHTMLの入力エラー文言とフォーカス表示は、生成回答のフォームで実際に露出するかを確認してから判断する。
- [unslop-ui](https://github.com/felipebasurto/unslop-ui) の `--surface` は、修正前後ともライセンス文書のダッシュ6件のみ検出。主要導線と検出候補ではSwiftUIの日本語の説明文、空状態、ラベル重複も手動で点検した。投稿の案内や資料名の重複は上表に記載。件数、処理状態、保存先、上限、選択マークは操作に必要な情報として保持する。
- 既定Listスタイル候補8件のうち、モデル選択は意図的に `.insetGrouped` を指定。PDF書き出し表示例とプレゼン表示例2件は診断用。実利用画面の投稿項目選択、資料添付、元の会議、プレゼン編集は、同じ種類のシートやエディターと見比べる。入力フォームと一覧の違いを踏まえて判断する。
- 残る画面確認は、記録詳細の再生・出典と要約失敗、ジャーナルの時刻と権限拒否、Ask AIの外部承認と生成フォーム、資料の書き出し失敗、人物の未確認候補、録音・復旧、設定12カテゴリ配下の復元・アクセス拒否。CloudKit、外部レコーダー、コミュニティの投稿には対応する接続環境が必要。iOS 26の実機と詳細なVoiceOver監査は保留。

## 改善の進め方

1. **データ保護と表示の整合** — U01〜U05・U09。隔離データで、ボタンが説明どおりの作用と状態を示すことを先に確認する。
2. **最優先の日常操作** — U06〜U08・U10〜U16。録音・保存、検索・入力、元記録への導線を、通常／最大文字、ライト／ダーク、キーボード表示中で確認する。
3. **未確認の下層と実機** — iOS 26と小さいiPhone、VoiceOver、許可拒否・取り消し、データ0件・1件・多数を使う。外部機器・同期・承認はテスト環境の資格情報と実機で確認する。
4. **非表示の機能は再有効化時に検証** — 通話のセットアップ・通話中、Live音声対話、画像版「1枚サマリー」はフラグで非表示。専用条件を満たした状態で、録音・権限・復旧やPNG書き出しを確認する。 [機能フラグ](../App/FeatureFlags.swift)

## 画面・シート候補の索引

機械抽出した索引。行部品・診断表示例を含む。実画面で見た範囲は本レポートの「点検範囲と根拠」を参照。

```sh
node tools/checks/ui-surface-audit.mjs --inventory
npx --yes @enmera/ai-design-check@0.16.3 App Shared --json
```

<details>
<summary>A（40件）</summary>

- [AIAnswerActionsExampleView.swift](../App/AIAnswerActionsExampleView.swift) · [AIAnswerTextSelectionView.swift](../App/AIAnswerTextSelectionView.swift) · [AIChatAttachmentSheet.swift](../App/AIChatAttachmentSheet.swift) · [AIChatModelSheet.swift](../App/AIChatModelSheet.swift) · [AIComposerInteractionExampleView.swift](../App/AIComposerInteractionExampleView.swift) · [AICreditsView.swift](../App/AICreditsView.swift)
- [AIHistoryDetailView.swift](../App/AIHistoryDetailView.swift) · [AIHistoryView.swift](../App/AIHistoryView.swift) · [AIInterfaceMetricView.swift](../App/AIInterfaceMetricView.swift) · [AIInterfaceStructuredExampleView.swift](../App/AIInterfaceStructuredExampleView.swift) · [AIMarkdownBaselineExampleView.swift](../App/AIMarkdownBaselineExampleView.swift) · [AIMarkdownPolishExampleView.swift](../App/AIMarkdownPolishExampleView.swift)
- [AIMemoryEditingExampleView.swift](../App/AIMemoryEditingExampleView.swift) · [AIMemoryEditor.swift](../App/AIMemoryEditor.swift) · [AIMemoryView.swift](../App/AIMemoryView.swift) · [AIMessageView.swift](../App/AIMessageView.swift) · [AIPluginIconView.swift](../App/AIPluginIconView.swift) · [AIPluginSetupView.swift](../App/AIPluginSetupView.swift)
- [AIQuestionView.swift](../App/AIQuestionView.swift) · [AISettingsView.swift](../App/AISettingsView.swift) · [AIUserMessageView.swift](../App/AIUserMessageView.swift) · [AIWaitingExampleView.swift](../App/AIWaitingExampleView.swift) · [APIKeySheet.swift](../App/APIKeySheet.swift) · [ActiveCallView.swift](../App/ActiveCallView.swift)
- [ActivityView.swift](../App/ActivityView.swift) · [AddPeopleSheet.swift](../App/AddPeopleSheet.swift) · [AddTaskView.swift](../App/AddTaskView.swift) · [AgentActivityView.swift](../App/AgentActivityView.swift) · [AgentPromptSuggestionsView.swift](../App/AgentPromptSuggestionsView.swift) · [AgentTaskDraftEditor.swift](../App/AgentTaskDraftEditor.swift)
- [AgentTaskDraftExampleView.swift](../App/AgentTaskDraftExampleView.swift) · [AgentTaskOperationCheckView.swift](../App/AgentTaskOperationCheckView.swift) · [AllMeetingsView.swift](../App/AllMeetingsView.swift) · [ArtifactSourceDetailView.swift](../App/ArtifactSourceDetailView.swift) · [ArtifactSourcesExampleView.swift](../App/ArtifactSourcesExampleView.swift) · [ArtifactSourcesView.swift](../App/ArtifactSourcesView.swift)
- [AskAIExperienceExampleView.swift](../App/AskAIExperienceExampleView.swift) · [AudioDiagnosticsView.swift](../App/AudioDiagnosticsView.swift) · [AudioSourceEvidenceCheckView.swift](../App/AudioSourceEvidenceCheckView.swift) · [AuthView.swift](../App/AuthView.swift)

</details>

<details>
<summary>B（1件）</summary>

- [BulkSpacePickerSheet.swift](../App/BulkSpacePickerSheet.swift)

</details>

<details>
<summary>C（30件）</summary>

- [CalendarEventEditor.swift](../App/CalendarEventEditor.swift) · [CalendarEventSheet.swift](../App/CalendarEventSheet.swift) · [CalendarSelectionView.swift](../App/CalendarSelectionView.swift) · [CallExplanationView.swift](../App/CallExplanationView.swift) · [CallIntroView.swift](../App/CallIntroView.swift) · [CallKeypadSheet.swift](../App/CallKeypadSheet.swift)
- [CallVerifiedView.swift](../App/CallVerifiedView.swift) · [CameraCaptureView.swift](../App/CameraCaptureView.swift) · [CaptureMenuSheet.swift](../App/CaptureMenuSheet.swift) · [CaptureSessionView.swift](../App/CaptureSessionView.swift) · [CloudShareSheet.swift](../App/CloudShareSheet.swift) · [CommunityAccountView.swift](../App/CommunityAccountView.swift)
- [CommunityCatalogView.swift](../App/CommunityCatalogView.swift) · [CommunityPostDetailView.swift](../App/CommunityPostDetailView.swift) · [CommunityPublishSheet.swift](../App/CommunityPublishSheet.swift) · [CompanyPresentationExampleView.swift](../App/CompanyPresentationExampleView.swift) · [CompanyPresentationExportView.swift](../App/CompanyPresentationExportView.swift) · [CompanyPresentationLayoutView.swift](../App/CompanyPresentationLayoutView.swift)
- [CompanyPresentationPreviewExampleView.swift](../App/CompanyPresentationPreviewExampleView.swift) · [CompanyPresentationPreviewSheet.swift](../App/CompanyPresentationPreviewSheet.swift) · [CompanyPresentationProfileView.swift](../App/CompanyPresentationProfileView.swift) · [CompanyPresentationReexportExampleView.swift](../App/CompanyPresentationReexportExampleView.swift) · [CompanyTemplateDetailView.swift](../App/CompanyTemplateDetailView.swift) · [CompanyTemplatesView.swift](../App/CompanyTemplatesView.swift)
- [ComposerDraftRecoveryView.swift](../App/ComposerDraftRecoveryView.swift) · [ConnectContactsView.swift](../App/ConnectContactsView.swift) · [ConnectorDetailSheet.swift](../App/ConnectorDetailSheet.swift) · [ConnectorHubView.swift](../App/ConnectorHubView.swift) · [ContentView.swift](../App/ContentView.swift) · [ConversationAttachmentView.swift](../App/ConversationAttachmentView.swift)

</details>

<details>
<summary>D（11件）</summary>

- [DesignSystemReviewView.swift](../App/DesignSystemReviewView.swift) · [DialerView.swift](../App/DialerView.swift) · [DocumentArtifactFileView.swift](../App/DocumentArtifactFileView.swift) · [DocumentArtifactHistoryView.swift](../App/DocumentArtifactHistoryView.swift) · [DocumentDetailView.swift](../App/DocumentDetailView.swift) · [DocumentEditSheet.swift](../App/DocumentEditSheet.swift)
- [DocumentPDFExportExampleView.swift](../App/DocumentPDFExportExampleView.swift) · [DocumentPDFExportProgressView.swift](../App/DocumentPDFExportProgressView.swift) · [DocumentRevisionExampleView.swift](../App/DocumentRevisionExampleView.swift) · [DocumentSlidesView.swift](../App/DocumentSlidesView.swift) · [DocumentsView.swift](../App/DocumentsView.swift)

</details>

<details>
<summary>E（3件）</summary>

- [EmailAuthView.swift](../App/EmailAuthView.swift) · [ExcludedPlacesView.swift](../App/ExcludedPlacesView.swift) · [ExternalRecorderSettingsView.swift](../App/ExternalRecorderSettingsView.swift)

</details>

<details>
<summary>F（2件）</summary>

- [FileCreationSheet.swift](../App/FileCreationSheet.swift) · [FileSidebarView.swift](../App/FileSidebarView.swift)

</details>

<details>
<summary>G（3件）</summary>

- [GlossaryMailSuggestionsView.swift](../App/GlossaryMailSuggestionsView.swift) · [GlossaryView.swift](../App/GlossaryView.swift) · [GmailSettingsView.swift](../App/GmailSettingsView.swift)

</details>

<details>
<summary>H（2件）</summary>

- [HealthReviewStatusView.swift](../App/HealthReviewStatusView.swift) · [HomeView.swift](../App/HomeView.swift)

</details>

<details>
<summary>I（7件）</summary>

- [IOSIntegrationSettingsView.swift](../App/IOSIntegrationSettingsView.swift) · [InlineCitationExampleView.swift](../App/InlineCitationExampleView.swift) · [InlineLinkSummaryView.swift](../App/InlineLinkSummaryView.swift) · [InlineMarkdownEditor.swift](../App/InlineMarkdownEditor.swift) · [IntegrationDetailView.swift](../App/IntegrationDetailView.swift) · [IntegrationsView.swift](../App/IntegrationsView.swift)
- [InteractionFeedbackView.swift](../App/InteractionFeedbackView.swift)

</details>

<details>
<summary>J（8件）</summary>

- [JSONRenderAnswerView.swift](../App/JSONRenderAnswerView.swift) · [JSONRenderExampleView.swift](../App/JSONRenderExampleView.swift) · [JSONRenderWebView.swift](../App/JSONRenderWebView.swift) · [JournalBackdropView.swift](../App/JournalBackdropView.swift) · [JournalMapSheet.swift](../App/JournalMapSheet.swift) · [JournalMovementSheet.swift](../App/JournalMovementSheet.swift)
- [JournalReviewView.swift](../App/JournalReviewView.swift) · [JournalSummaryView.swift](../App/JournalSummaryView.swift)

</details>

<details>
<summary>L（12件）</summary>

- [LLMModelPickerView.swift](../App/LLMModelPickerView.swift) · [LLMProviderPickerView.swift](../App/LLMProviderPickerView.swift) · [LibraryDestinationView.swift](../App/LibraryDestinationView.swift) · [LibraryView.swift](../App/LibraryView.swift) · [LicenseActivationView.swift](../App/LicenseActivationView.swift) · [LifeLogCreationSheet.swift](../App/LifeLogCreationSheet.swift)
- [LifeLogEditSheet.swift](../App/LifeLogEditSheet.swift) · [LifeLogEntryDetailView.swift](../App/LifeLogEntryDetailView.swift) · [LocalSourceMediaPlayerView.swift](../App/LocalSourceMediaPlayerView.swift) · [LocalSourcePDFView.swift](../App/LocalSourcePDFView.swift) · [LocalVoiceModelSetupView.swift](../App/LocalVoiceModelSetupView.swift) · [LockScreenView.swift](../App/LockScreenView.swift)

</details>

<details>
<summary>M（24件）</summary>

- [MCPServerEditor.swift](../App/MCPServerEditor.swift) · [MCPServersView.swift](../App/MCPServersView.swift) · [MCPServiceSettingsView.swift](../App/MCPServiceSettingsView.swift) · [MCPSettingsView.swift](../App/MCPSettingsView.swift) · [MailDraftSheet.swift](../App/MailDraftSheet.swift) · [MailDraftsView.swift](../App/MailDraftsView.swift)
- [MarkdownBlockView.swift](../App/MarkdownBlockView.swift) · [MarkdownDocumentView.swift](../App/MarkdownDocumentView.swift) · [MarkdownTableView.swift](../App/MarkdownTableView.swift) · [MarketplaceCatalogView.swift](../App/MarketplaceCatalogView.swift) · [MarketplaceDetailSheet.swift](../App/MarketplaceDetailSheet.swift) · [MarketplaceHomeView.swift](../App/MarketplaceHomeView.swift)
- [MarketplaceInstalledView.swift](../App/MarketplaceInstalledView.swift) · [MeetingDetailView.swift](../App/MeetingDetailView.swift) · [MeetingHighlightsEditor.swift](../App/MeetingHighlightsEditor.swift) · [MeetingInfographicEvidenceView.swift](../App/MeetingInfographicEvidenceView.swift) · [MeetingInfographicGenerationSheet.swift](../App/MeetingInfographicGenerationSheet.swift) · [MeetingInfographicPanelView.swift](../App/MeetingInfographicPanelView.swift)
- [MeetingQuestionSuggestionsView.swift](../App/MeetingQuestionSuggestionsView.swift) · [MeetingSummaryPosterGroupView.swift](../App/MeetingSummaryPosterGroupView.swift) · [MeetingSummaryPosterSectionView.swift](../App/MeetingSummaryPosterSectionView.swift) · [MeetingSummaryPosterSheet.swift](../App/MeetingSummaryPosterSheet.swift) · [ModelCapabilitiesView.swift](../App/ModelCapabilitiesView.swift) · [MotionLoadingGalleryView.swift](../App/MotionLoadingGalleryView.swift)

</details>

<details>
<summary>N（3件）</summary>

- [NativeAIInterfaceExampleView.swift](../App/NativeAIInterfaceExampleView.swift) · [NativeAIInterfaceView.swift](../App/NativeAIInterfaceView.swift) · [NotionSettingsView.swift](../App/NotionSettingsView.swift)

</details>

<details>
<summary>O（6件）</summary>

- [OccupationSelectionView.swift](../App/OccupationSelectionView.swift) · [OmiDeviceDetailView.swift](../App/OmiDeviceDetailView.swift) · [OmiPairingView.swift](../App/OmiPairingView.swift) · [OnboardingView.swift](../App/OnboardingView.swift) · [OnlineMeetingCaptureView.swift](../App/OnlineMeetingCaptureView.swift) · [OpenSourceLicensesView.swift](../App/OpenSourceLicensesView.swift)

</details>

<details>
<summary>P（35件）</summary>

- [PDFSourcePartitionSheet.swift](../App/PDFSourcePartitionSheet.swift) · [PaywallView.swift](../App/PaywallView.swift) · [PeopleManagerSheet.swift](../App/PeopleManagerSheet.swift) · [PeopleView.swift](../App/PeopleView.swift) · [PerformanceLogView.swift](../App/PerformanceLogView.swift) · [PersonDetailView.swift](../App/PersonDetailView.swift)
- [PersonEditSheet.swift](../App/PersonEditSheet.swift) · [PhoneNumberEntryView.swift](../App/PhoneNumberEntryView.swift) · [PhoneVerificationView.swift](../App/PhoneVerificationView.swift) · [PhotoEditingExampleView.swift](../App/PhotoEditingExampleView.swift) · [PhotoEditorView.swift](../App/PhotoEditorView.swift) · [PlaudConnectionView.swift](../App/PlaudConnectionView.swift)
- [PresentationCatalogView.swift](../App/PresentationCatalogView.swift) · [PresentationEditingExampleView.swift](../App/PresentationEditingExampleView.swift) · [PresentationEditorView.swift](../App/PresentationEditorView.swift) · [PresentationQualityView.swift](../App/PresentationQualityView.swift) · [PresentationRevisionView.swift](../App/PresentationRevisionView.swift) · [PresentationSlideEditor.swift](../App/PresentationSlideEditor.swift)
- [PrivacyStorageView.swift](../App/PrivacyStorageView.swift) · [ProfileEditorView.swift](../App/ProfileEditorView.swift) · [ProjectChatRenameSheet.swift](../App/ProjectChatRenameSheet.swift) · [ProjectChatView.swift](../App/ProjectChatView.swift) · [ProjectChatsView.swift](../App/ProjectChatsView.swift) · [ProjectFilePickerSheet.swift](../App/ProjectFilePickerSheet.swift)
- [ProjectNoteAttachSheet.swift](../App/ProjectNoteAttachSheet.swift) · [ProjectNoteEditSheet.swift](../App/ProjectNoteEditSheet.swift) · [ProjectPDFView.swift](../App/ProjectPDFView.swift) · [ProjectSourceAddSheet.swift](../App/ProjectSourceAddSheet.swift) · [ProjectSourceDetailView.swift](../App/ProjectSourceDetailView.swift) · [ProjectSourceOperationCheckView.swift](../App/ProjectSourceOperationCheckView.swift)
- [ProjectSourcePrivacySheet.swift](../App/ProjectSourcePrivacySheet.swift) · [ProjectSourcesView.swift](../App/ProjectSourcesView.swift) · [ProjectTaskOperationCheckView.swift](../App/ProjectTaskOperationCheckView.swift) · [ProjectTasksView.swift](../App/ProjectTasksView.swift) · [ProjectsView.swift](../App/ProjectsView.swift)

</details>

<details>
<summary>R（14件）</summary>

- [RealtimeTranscriptView.swift](../App/RealtimeTranscriptView.swift) · [RecentlyDeletedView.swift](../App/RecentlyDeletedView.swift) · [RecordPrivacySettingsView.swift](../App/RecordPrivacySettingsView.swift) · [RecordProcessingStateView.swift](../App/RecordProcessingStateView.swift) · [RecorderAudioImportView.swift](../App/RecorderAudioImportView.swift) · [RecordingMarkersView.swift](../App/RecordingMarkersView.swift)
- [RecordingMethodSheet.swift](../App/RecordingMethodSheet.swift) · [RegisteredLLMEditor.swift](../App/RegisteredLLMEditor.swift) · [RegisteredLLMsView.swift](../App/RegisteredLLMsView.swift) · [RenameMeetingSheet.swift](../App/RenameMeetingSheet.swift) · [RenameSpaceSheet.swift](../App/RenameSpaceSheet.swift) · [ResidentAgentEditor.swift](../App/ResidentAgentEditor.swift)
- [ResidentAgentsView.swift](../App/ResidentAgentsView.swift) · [RootTabView.swift](../App/RootTabView.swift)

</details>

<details>
<summary>S（34件）</summary>

- [SearchView.swift](../App/SearchView.swift) · [SettingsBackupView.swift](../App/SettingsBackupView.swift) · [SettingsCategoryView.swift](../App/SettingsCategoryView.swift) · [SettingsNotesView.swift](../App/SettingsNotesView.swift) · [SettingsView.swift](../App/SettingsView.swift) · [ShareInboxView.swift](../App/ShareInboxView.swift)
- [SharedProjectView.swift](../App/SharedProjectView.swift) · [SharedRecordView.swift](../App/SharedRecordView.swift) · [SidebarHeaderView.swift](../App/SidebarHeaderView.swift) · [SkillDetailView.swift](../App/SkillDetailView.swift) · [SkillEditorView.swift](../App/SkillEditorView.swift) · [SkillsView.swift](../App/SkillsView.swift)
- [SlideLayoutExampleView.swift](../App/SlideLayoutExampleView.swift) · [SlideView.swift](../App/SlideView.swift) · [SourceMediaPlayerView.swift](../App/SourceMediaPlayerView.swift) · [SourceSummaryOptionsSheet.swift](../App/SourceSummaryOptionsSheet.swift) · [SpaceDetailView.swift](../App/SpaceDetailView.swift) · [SpacePickerSheet.swift](../App/SpacePickerSheet.swift)
- [SpeakerEditSheet.swift](../App/SpeakerEditSheet.swift) · [SpeakerIdentificationSettingsView.swift](../App/SpeakerIdentificationSettingsView.swift) · [SpeechRecognitionSettingsView.swift](../App/SpeechRecognitionSettingsView.swift) · [StateGalleryView.swift](../App/StateGalleryView.swift) · [StorageUsageView.swift](../App/StorageUsageView.swift) · [StreamingMarkdownView.swift](../App/StreamingMarkdownView.swift)
- [SummaryDiagnosticsView.swift](../App/SummaryDiagnosticsView.swift) · [SummaryExtractionView.swift](../App/SummaryExtractionView.swift) · [SummaryFactEditor.swift](../App/SummaryFactEditor.swift) · [SummaryGenerationSheet.swift](../App/SummaryGenerationSheet.swift) · [SummaryHistoryDetailView.swift](../App/SummaryHistoryDetailView.swift) · [SummaryHistoryView.swift](../App/SummaryHistoryView.swift)
- [SummaryStyleSettingsView.swift](../App/SummaryStyleSettingsView.swift) · [SummaryTemplateDetailView.swift](../App/SummaryTemplateDetailView.swift) · [SummaryTemplateEditor.swift](../App/SummaryTemplateEditor.swift) · [SummaryTemplateMarketplaceView.swift](../App/SummaryTemplateMarketplaceView.swift)

</details>

<details>
<summary>T（10件）</summary>

- [TaskEditView.swift](../App/TaskEditView.swift) · [TasksView.swift](../App/TasksView.swift) · [TeamCreateSheet.swift](../App/TeamCreateSheet.swift) · [TeamJoinSheet.swift](../App/TeamJoinSheet.swift) · [TeamSharesView.swift](../App/TeamSharesView.swift) · [TeamTaskBoardView.swift](../App/TeamTaskBoardView.swift)
- [ThinkingOrbView.swift](../App/ThinkingOrbView.swift) · [ThinkingTraceView.swift](../App/ThinkingTraceView.swift) · [ToolsView.swift](../App/ToolsView.swift) · [TranscriptView.swift](../App/TranscriptView.swift)

</details>

<details>
<summary>V（2件）</summary>

- [VideoTranscriptImportSheet.swift](../App/VideoTranscriptImportSheet.swift) · [VoiceProfileView.swift](../App/VoiceProfileView.swift)

</details>

<details>
<summary>W（8件）</summary>

- [WebResearchDetailView.swift](../App/WebResearchDetailView.swift) · [WebResearchSaveSheet.swift](../App/WebResearchSaveSheet.swift) · [WebResearchSettingsView.swift](../App/WebResearchSettingsView.swift) · [WebResearchView.swift](../App/WebResearchView.swift) · [WebSourceEvidenceCheckView.swift](../App/WebSourceEvidenceCheckView.swift) · [WebhookEditor.swift](../App/WebhookEditor.swift)
- [WebhookSettingsView.swift](../App/WebhookSettingsView.swift) · [WorkspaceSettingsView.swift](../App/WorkspaceSettingsView.swift)

</details>

<details>
<summary>名称条件外のナビゲーション候補（13件）</summary>

- [AIAnswerActions.swift](../App/AIAnswerActions.swift)
- [AIComposerBar.swift](../App/AIComposerBar.swift)
- [AttachmentCitationList.swift](../App/AttachmentCitationList.swift)
- [CallSetupFlow.swift](../App/CallSetupFlow.swift)
- [CommunitySubmissionPicker.swift](../App/CommunitySubmissionPicker.swift)
- [ComposerDraftRecoveryPrompt.swift](../App/ComposerDraftRecoveryPrompt.swift)
- [ComposerMentionStrip.swift](../App/ComposerMentionStrip.swift)
- [JournalPeopleFields.swift](../App/JournalPeopleFields.swift)
- [JournalPlacePicker.swift](../App/JournalPlacePicker.swift)
- [PresentationPlanFields.swift](../App/PresentationPlanFields.swift)
- [QuickAIComposer.swift](../App/QuickAIComposer.swift)
- [TaskDocumentPicker.swift](../App/TaskDocumentPicker.swift)
- [TaskMeetingPicker.swift](../App/TaskMeetingPicker.swift)

</details>
