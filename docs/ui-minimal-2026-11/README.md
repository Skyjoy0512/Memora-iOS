# 2026-11-01 主要画面をミニマルに整理

2026-11-02の最新指定で、作成操作を下部の独立したメモ／＋へ移動した。
右上の＋は撤去し、Ask AIを左へ寄せた横並びとする。以下の以前の右上配置の
操作記録・画像は、その時点の履歴として保持する。

最新の利用者指定により、Library / Projectsの切替は従来のピル型タブへ戻した。
資料は3件で打ち切らず、全件を同じListに並べる。「すべて見る」は撤去。
以下のタイトルメニュー案の操作記録は途中段階として保持する。

利用者の指示に沿い、録音を最優先に戻し、ChatGPTのように内容と入力に集中できる
簡素な画面へ整理した。ChatGPTの非公開寸法の再現ではなく、既存のMemoraの色・
文字・Lucideアイコンとnative操作を使う。開始時main / `bb2c34fe`、未コミット変更なし。

## 変更

| 対象 | 変更前 | 変更後 |
|---|---|---|
| 作成 | 右上＋に録音・メモ・資料等を集約 | 下部のメモ／＋に分離。＋側は録音が先頭。project作成はProjectsのその他／空状態へ |
| Library | 途中段階でタイトルメニューへ変更 | 従来のピル型切替へ復帰。隣のメニューに表示・並べ替え・絞り込み・選択を保持 |
| Libraryの参考資料 | 先頭3件と「すべて見る」 | 全件を同じlazy Listへ表示し、スクロールで探す |
| Projects | さらに別の絞り込み列 | 1つのその他メニューに表示条件を集約 |
| 資料行 | 正常時にも状態を反復。ダーク表示で黒い行背景 | タイトルと補足情報を中心にし、背景を統一。取得不足・失敗・準備中は表示 |
| Ask AI | 入力欄のglass装飾と高さ、サイドバーの追加装飾 | 最新指定で標準Liquid Glassへ変更。折りたたみ時56pt。native TextFieldとIMEを維持 |
| 資料詳細 | 種類・著者・日付が別々の行、大きい質問ボタン | 補足情報をまとめ、質問は静かなinline操作。履歴等は補足領域へ |
| Journal | タスク0件でも見出し・説明・全件リンク | 0件時はタスクへの1つのリンク。タスクがある場合は従来の一覧 |

録音は既存の処理・保存先を使い、権限確認を迂回しない。右上＋、下部Ask AI composer、
検索・選択時のcomposer非表示、共通navigation path、保存済み表示設定を保持。
プロジェクト作成、取り込み、メモ、オンライン会議、会話作成は引き続き到達可能。
資料詳細の原文・ページ/時刻リンク・再試行・要約設定・引用移動も保持。
データ構造・会話履歴・機密設定・AI送信設定は変更せず、移行は不要。
Marketplaceの画面・カード・アートワーク・共通色tokenは変更していない。

## 実際の画面比較

すべて同じシミュレーターの実スクリーンショット。Ask AIの既存会話は保存画像に含めない。

| 画面 | 変更前 | 変更後 |
|---|---|---|
| ライブラリ | [画像](images/library-before.png) | [画像](images/library-after.png) |
| ＋メニュー | [画像](images/create-menu-before.png) | [画像](images/create-menu-after.png) |
| プロジェクト | [画像](images/projects-before.png) | [画像](images/projects-after.png) |
| 参考資料の全件一覧 | [画像](images/source-list-before.png) | [画像](images/source-list-after.png) |
| 資料詳細の原文導線 | 撮影なし | [画像](images/source-detail-after.png) |

## 検証

- `bitrig preview -platform iOS` 成功。プレビューを更新済み。
  最終ログはBitrig Buildsの `logs/2026-11-01T22-47-14-7b1a02ca.log`。
  既存の非推奨API等の警告11件。新規APIやproject設定の変更なし。
- シミュレーター（iPhone 18 Pro / 日本語 / ダーク）で、LibraryとProjectsの切替、
  両方の＋メニューで「録音する」が先頭であること、Projectsの作成項目が残ることを目視確認。
  Libraryの背景修正、資料詳細の表示と原文の開閉、元ページリンクと質問操作の表示、
  Ask AIの既存会話表示・空の入力欄へのキーボード表示も確認。
- 録音開始・新規データ作成・AI送信は実行していない。既存会話や資料を消していない。
  元ページリンクと質問操作の実行結果、非空Projects、Journalの新しい空タスク表示、
  小画面・ライトモード・実機・VoiceOverはこのフェーズでは未検証。
- simulatorのAX取得が失敗したため、画面画像に基づく座標操作で確認した。
  アクセシビリティ動作確認済みとは扱わない。
- 利用者の費用方針に従い、変更単位のテスト追加・全host検査の反復は行わず、
  UIフェーズのビルドと主要操作確認をまとめて実施。画像で見つかったList背景を修正後に
  最終previewを実行した。情報取り込み全体の受け入れ検証とは別の記録である。

従来の音声・AIサービス・長大PDF等の実機検証残件は
[情報ソース監査の検証記録](../source-audit/VALIDATION.md)を参照。

## 追加整理

同じ方向で再点検した段階の開始時はmain / `d3ec77b8`、未コミット変更なし。
次の不統一を静的コードから見つけ、追加修正した。

- `SpaceDetailView` の作成操作が表示別に別実装だったため、右端に共通の＋を置き、
  どの表示でも「録音する」を先頭にした。作成は＋、移動・共有・名前変更等はその他へ整理。
  新しいチャットだけは既存のプロジェクト内会話作成をcallbackで使い、global会話へ切り替えない。
- プロジェクト名の下に現在の表示を示し、同じタイトルメニューでチャット・記録・参考資料を切替。
  常設のタブ列を省き、一覧の場所を広げた。空状態・移動・関連タスク・共有・削除確認は保持。
- 新規Ask AIは大見出し・キャッチコピー・常時説明文と、候補ごとに繰り返す補足・矢印を除いた。
  具体的な候補と元の資料名を残す。候補は引き続き下書きに入るだけで、自動送信しない。
  下書きや添付があるときの候補無効化、理由、権限・承認処理を維持。
- `ProjectSourcesView` にも黒いList行背景が残っていたため、Libraryと同じ背景・左右余白へ揃えた。
  資料専用追加はpaperclipで示し、録音を含む汎用の＋と区別した。

この追加整理もMarketplace、設定、保存データ、取り込み・録音エンジンは変更していない。

追加分の `bitrig preview -platform iOS` は成功（既存警告11件）。ログは
Bitrig Buildsの `logs/2026-11-01T22-56-34-b37a89b7.log`。
変更前の全件一覧の黒い背景を実際に確認し、更新後は統一された背景とpaperclipを目視確認。
Libraryの＋メニューも再確認し、録音が先頭だった。比較画像を上表へ追加した。
既存会話やプロジェクトを変更せず確認したため、プロジェクト詳細の新メニューと
Ask AIの新規状態はコードレビュー・ビルドまでで、実表示・操作は未検証。
録音開始・外部送信・実機・追加アクセシビリティ検証、全テスト反復は行っていない。

## ピル切替と全件スクロール

利用者の再指定に沿い、`MemoraTextTabBar` を復帰し、表示名を「ファイル / プロジェクト」に揃えた。
タイトルはLibraryのまま、ファイル側の表示条件はタブ横のnativeメニューへ置いた。
検索・ファイル選択中はこれまでどおりタブ列を隠し、共有navigation pathと選択設定を維持する。
資料の `prefix(3)` と「すべて見る」の別画面リンクを除去し、検索時以外も全件を同じListに渡す。
Listによる行の遅延生成を使い、架空の追加取得や無制限のネットワーク読込は加えない。
Marketplaceの棚と「すべて見る」は維持する。

## 控えめな表示演出 — 2026-11-02

- Library・Journal・Ask AIの主コンテンツ、Libraryの各詳細遷移、設定フォームに
  約0.32秒の初回フェードを追加。通常は4ptだけ持ち上がり、Reduce Motionでは移動しない。
- 資料・録音・生成文書の見出しは約0.4秒でテキストを表示。本文の読む速度を制限しない。
- 新しく生成中のAI回答だけ、最初の本文に約0.36秒の導入を適用。
  以後のtoken到着・過去回答・一覧の各行には追加の再生や待ち時間を入れない。
  導入済みmessage IDを最大128件保持し、スクロールによる再生成で繰り返さない。
- 文字選択・Markdown・引用・表は既存構造を維持。Reduce Motionのテキストは即表示。
  Marketplace・書き出し用rendererには演出を追加していない。

ライブAIの生成・各画面の動きを
動画で計測した検証、実機・追加のアクセシビリティ検証は未実施。

## Ask AI入力欄のLiquid Glass — 2026-11-02

共通の`AIComposerBar`を不透明card＋手描きの枠線から、既存`memoraGlass`の
untinted regular＋interactiveへ変更。`backed: false`で追加materialを重ねず、
全体・プロジェクト・資料詳細・回答シートの入力欄に同じ素材を適用する。
小さい状態のcapsule／入力中の角丸形状と既存のfocus/IME/添付/送信処理を維持。
iOS26未満の既存fallbackも共通部品に残し、透明度を下げる設定はnative glassに従う。
ページ全体やMarketplaceのカードには適用しない。

## 最終確認 — 2026-11-02

`bitrig preview -platform iOS` 成功（既存警告11件）、利用者のプレビュー更新済み。
log: `logs/2026-11-02T07-12-10-464695c9.log`。
iPhone18 Pro／ダーク表示の実画面で以下を確認した。

- 「ファイル / プロジェクト」のピル表示、プロジェクトからファイルへの切替。
- 参考資料の下の「すべて見る」が消え、同じ一覧で表示されること。
  実データは1件のため、4件目以降の実スクロールは未確認。全件渡しはコードで確認した。
- 下部composerのLiquid Glassの輪郭・半透明表現。入力欄tapでキーボードと
  2段の角丸入力面が表示され、外側tapでコンパクトな形状に戻ること。
  文字入力・送信・音声入力・実AI呼出しはこの確認では実行していない。

| 更新後 | 比較画像 |
|---|---|
| ファイル一覧・ピル・コンパクトなglass入力欄 | [画面](images/library-pills-after.png) |
| プロジェクトの空状態・同じglass入力欄 | [画面](images/projects-pills-glass-after.png) |
| 入力中の角丸glassとキーボード | [画面](images/composer-glass-focused-after.png) |

AX状態取得が失敗したため、画像と座標tapで確認した。動きの時間計測・
ライブ生成中のテキストリビール・ライト表示・小画面・実機・追加アクセシビリティ検証は未実施。
一覧や既存会話の内容は変更せず、Marketplaceの画面も変更していない。

## 下部のAsk AI・メモ・録音 — 2026-11-02

最新指定により、下部の横並びを「Ask AI / メモ / マイク」にした。
独立した52ptのglass円と8ptの間隔、左右12ptを使い、入力欄は残り幅へ自然に伸縮する。

- メモ: メモを書く / 資料を追加。
- マイク: 録音する / 音声を取り込む / オンライン会議を録音。
- native Menuと既存CaptureAction・資料追加・音声取込を再利用。録音の開始や保存先を
  別実装にせず、現在のvisibleProjectIDと音声選択開始時のLocalImportContextを引き継ぐ。
- Library・Journal・プロジェクト詳細の右上＋を除去。Projectsのその他メニューに
  project作成、project詳細のその他に新しいチャットを残し、既存の空状態も維持。
- idleの入力欄から音声入力マイクを省き、録音マイクと区別。入力中は全幅になり、
  既存のメッセージ音声入力・添付・送信・停止は拡大した入力欄に保持する。
- 検索・選択・入力中はcaptureラベルを不可視・非操作とし、fileImporterのhostは保持。
  共有の読取専用資料では作成ボタンを隠す。Marketplaceは変更していない。
- フォーカスを外した下書き・添付があっても作成ボタンは使える。録音するために
  下書きを捨てる必要はない。キーボード表示中だけ入力の幅を優先する。

表示確認で、glass container内の添付＋が薄く描画されることと、外側opacityだけでは
非表示のcapture glassが残ることを確認した。添付操作をglassのforegroundへ含め、
非表示のcircle表面だけを除去し、importerは同じviewに保持するよう修正した。

| 比較 | 画像 |
|---|---|
| 変更前の右上統合メニュー | [画面](images/capture-menu-before.png) |
| 変更後の下部横並び | [画面](images/capture-row-after.png) |
| メモ側の2項目 | [画面](images/capture-memo-menu-after.png) |
| マイク側の3項目・録音先頭 | [画面](images/capture-record-menu-after.png) |
| 入力中の全幅表示・circle残像なし | [画面](images/capture-row-focused-after.png) |

iPhone18 Pro／ダークのsimulatorで、上の配置・両メニューの数と順序、音声インポートから
native file pickerへの遷移、pickerの検索キーボード表示中も維持されること、取消で戻ることを確認。
AX読み取りが失敗したため画像と座標tapで確認した。録音開始・実ファイル選択・保存・
オンライン会議の録音・実機・追加アクセシビリティ検査は実行していない。
UIの区切りでpreviewと主要操作を確認し、全host検査の反復や新しい単体テスト追加は行わない。

最終 `bitrig preview -platform iOS` 成功、プレビュー更新済み。log:
`logs/2026-11-02T07-50-41-5966b64b.log`、既存警告11件。
最終版で通常表示・両メニュー・入力focus時の全幅表示とcircle残像なし・blur後の復帰、
音声pickerの検索キーボード・取消を再確認。入力文字・送信・保存は実行していない。
待機中の下書きがある場合の作成ボタン維持は静的確認で、文字を入力した操作試験ではない。
`git diff --check`通過。既存データの変更・移行とSDK27.1より新しいAPI追加はない。

## 下部メニューの遷移と録音開始保護 — 2026-11-02

オンライン会議の準備画面から録音へ移る処理に、固定250msの待機が残っていた。
sheetの`onDismiss`で明示的な開始要求だけを引き継ぎ、閉じる・スワイプ終了では開始しない。
準備画面を開いた時点の保存先contextは保持し、別workspaceへの切替・復元・保護状態への
移行・projectの変更/削除後は無効にする。中断した開始要求を永続化・自動再開しない。

共通`startCapture`も、既存録音の復旧、マイク許可、音声session取得のawaitの前後で
LocalImportContextを確認する。定例会議から決まるprojectも許可要求前に固定する。
session取得後に依頼が失効していた場合は停止し、その開始で作った未保存fileのみ削除する。
既存の録音・復旧draftや利用者の音声を削除しない。保存データの移行は不要。

確認はこの変更範囲に絞った。

- `python3 tools/checks/run-recording-start-checks.py` 成功。productionの録音開始methodと
  `LocalImportContext`を実行し、24の失効境界、正常開始・二重開始抑止・許可拒否・
  定例project変更・取消を確認。マイク・音声session・永続化・UIはfixtureで、
  実音声ファイルの作成/削除やiOS callbackの発火はこの検査の対象外。
- capture・native navigation・composerの表示契約の4件、motion policy検査を限定実行し成功。
  旧`CaptureToolbarButton`の参照と「全画面のfade禁止」は最新の利用者指定に合わせた。
  全suiteや追加のアクセシビリティ検査は実行していない。

実画面の確認で、native Menuの下部項目をAsk AIのglass表面と重なる位置で押すと
反応しないことを確認した。メモ側の先頭項目、オンライン会議項目の上端では遷移した。
下部3操作を包む共通glass containerを外し、それぞれのnative glassを独立させる。
配置と個々のglass素材は維持する。

最終 `bitrig preview -platform iOS` 成功、既存警告11件、プレビュー更新済み。
log: `logs/2026-11-02T08-04-20-cd9161f8.log`。
iPhone18 Pro／ダークのsimulatorで、修正前と同じ座標にある資料追加項目の中央
`(196,807)`とオンライン会議項目の中央`(260,796)`をtapし、それぞれのsheetへの遷移を確認。
メモ作成画面への遷移も確認した。AX読み取りは失敗したため画像・座標で確認している。
オンライン会議画面は録音準備ボタンを押さずに閉じ、通常の一覧へ戻ることを確認した。
[オンライン会議の遷移後](images/capture-online-sheet-after.png)。
実録音開始・許可ダイアログ・音声session取得・スワイプ終了・実機の操作は未検証。
既存データの編集・新しい資料保存・AI送信は実行していない。

## 右端の＋と入力時のFAB形状 — 2026-11-02

利用者の指定に従い、右端のglyphをマイクから＋へ変更した。既存Lucideの`MemoraIcon.plus`
を使用し、メニューは録音/音声取込/オンライン会議の3項目を維持する。
読み上げ名は「録音メニュー」で、メモと資料のメニューとは分けている。

入力欄の拡大時もFABの実体は52ptの円形に固定する。縮めるのは外側の予約領域だけ。
glass付きLabelと透明Viewの差し替えをやめ、同じLabelのopacityで表示を切り替える。
FAB内部には親のlayout animationを伝えず、composerの拡大とglass形状の補間を分離した。
個々のglassは独立させたままで、共通glass containerは戻していない。
メニュー・fileImporterは非表示時もmountedのまま維持し、入力中は操作を無効にする。

`bitrig preview -platform iOS` 成功（既存警告11件）、プレビュー更新済み。
log: `logs/2026-11-02T08-10-57-d559a3e6.log`。
iPhone18 Pro／ダークのsimulatorで右端の＋、同じ3項目のメニュー、Ask AIを押すと
入力欄が全幅になりFAB表面が残らないこと、外側tapで円形のFABが戻ることを確認。
AX取得は失敗したため画像と座標で操作した。切替途中の全フレーム計測や実機検証は未実施。
文字入力・送信・録音・データ保存は実行していない。既存の表示契約2件とmotion policyのみ
限定実行し成功、全suiteの反復・新しいテスト追加・追加アクセシビリティ検証は行わない。

| 状態 | 画像 |
|---|---|
| 右端＋・52ptの独立した円形 | [通常表示](images/capture-plus-row-after.png) |
| Ask AI入力時・全幅、FABなし | [入力状態](images/capture-plus-focused-after.png) |

## FAB固定配置・複数選択・メモ導線 — 2026-11-02

前回の固定サイズ/opacityだけでは入力時の違和感が残るとの報告を受け、FABを
入力欄と同じ横並びlayoutから固定trailing overlayへ移した。入力欄はtrailing paddingを
変えるだけで、FAB hostの幅/高さ/位置は補間しない。非表示時はvisual Menuだけを
animationなしで除去し、fileImporter/dialogのhostは常時mountedのまま保持する。
通常時のメモ・＋、そのメニュー内容・glass素材・Marketplaceは維持。

ライブラリの複数選択時に名前が重なるとの報告に対し、選択markを別列に追加する構造を
やめ、既存source iconのslotへ置く。タイトルの利用幅が選択前後で変わらず、
`LibraryRecordRow`/`ProjectRecordRow`は必要な高さをlayoutへ伝える。
個々の選択toggleでList全体をanimationしない。既存の診断画面のDEBUG領域に、
同じproduction rowを使う長い日本語タイトル3件の選択例を追加した。
架空データはmemory内のみで、SQLite・録音・外部AIは使わない。

作成メニューとsystem memo linkは、既存の`ProjectSourceAddSheet`のmemo modeへ接続。
本文・任意タイトル・保存先だけを表示し、開いている個人projectまたはLibraryへ
従来の`ProjectSource.note`として保存する。URLだけを貼った場合は通常の資料追加と同じ
安全なリンク取得経路へ接続し、入口によって解析結果を変えない。旧Journalのメモを移動・変換せず、
日付指定のJournal作成は既存の`LifeLogCreationSheet`へ残す。

メモは保存先別に`workspace.newMemo.<project/library>`のDraftStoreを使い、
既存の資料追加`workspace.newNote`と混ぜない。画面を開いた時点のLocalImportContextを
保存時/下書き更新時に再検査し、note本体のSQLite登録と2つのdraft key削除を同じ
transactionにした。失敗なら本文fileをrollbackしてdraftを維持する。成功後の自動要約は
既存の送信許可/AI設定に従う。既存データのschema変更や一括移行はない。

限定検査: `run-project-source-storage-checks.sh` PASS。production note/store path、
実file/SQLite再読込、既存24の競合に加え、draft削除にSQL failureを注入して
note登録・file・draftのrollbackと再試行成功を確認した。最初の追加fixtureは空の
作業directory未作成で失敗し、fixtureの初期化を修正して最終実行は成功した。
表示契約2件とmotion policyは成功。全suiteや実外部AIの反復試験はしていない。

初回preview成功後、simulatorのLibraryで「メモを書く」の保存先・簡潔な表示と
入力した検証用draftの閉じる→開き直す復元を確認。検証用本文は空へ戻して閉じ、
資料保存・AI送信は実行していない。projectへの実操作は未確認で、保存先保持はhost検査と
静的な導線確認の範囲。

iPhone18 Pro／ダークのsimulatorで次を確認した。AX取得は失敗したため画像と座標で操作した。

- DEBUGの既存「デザインと保存の検証」で、長い日本語タイトル3件の通常→複数選択→
  2件選択→通常への復帰。タイトルの開始位置・折り返し・行高が変わらず重ならない。
  同じproduction rowによる表示確認であり、実際のLibrary全体の選択bar/削除/移動を
  実データで試した証拠ではない。架空のMeetingは保存していない。
- Ask AI入力時のFAB非表示・入力欄全幅・blur後のメモ/＋復帰。native音声file pickerを開き、
  検索keyboard中も維持されることと取消後の復帰。音声fileの選択/取り込みはしていない。
- メモの新しい表題とLibrary保存先、未保存の検証用draftの閉じる→再表示での復元。
  確認用本文は空へ戻した。旧Journalデータや既存資料の編集・録音・実AI送信は行わない。

FAB遷移途中の全フレーム計測、実機、project内からの新規メモ操作、単独URLの今回の
実取得は未検証。追加アクセシビリティ検査・全host suiteの反復もしていない。

| 今回の確認 | 画像 |
|---|---|
| 長いタイトル・通常表示（production rowの架空表示例） | [通常](images/library-long-names-normal-after.png) |
| 同じ幅・高さで2件を選択 | [複数選択](images/library-selection-long-names-after.png) |
| 固定overlayのFABを除いたAsk AI入力状態 | [入力状態](images/capture-fixed-overlay-focused-after.png) |

最終 `bitrig preview -platform iOS` 成功、既存警告11件、プレビュー更新済み。
log: `logs/2026-11-02T08-29-31-550da365.log`。
上の選択例/FAB/file pickerの操作は直前の`08:23:54-ce4be34b`版で実施した。
最後の変更は単独URLのmode分岐を外して従来の共通取得へ揃える修正とindent整形。
最終版の通常画面の起動を確認した。単独URLでの新たな通信/AI試験や全検査の反復はしていない。
