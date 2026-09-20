# Memora — Zero-based Product & UI Design

## A. Product understanding

Memoraは、音声を保管するアプリではなく、会話を「あとから使える知識」に変えるアプリである。中心価値は、ユーザーが録音以外をほぼ操作しなくても、会話が要約・決定・タスク・未決事項へ変換され、元の発言まで戻れることにある。

設計上の短い定義は、**Record once. Move forward.**。録音後の整理を仕事としてユーザーへ返さない。

## B. Primary jobs

頻度と緊急性から、Jobを次の順に置く。

1. 会議が始まった瞬間に迷わず録音する
2. 会議後すぐ、結論と次の行動だけを把握する
3. 必要な時に、過去の発言や決定を根拠付きで探す
4. 複数の会議から生まれたタスクをまとめて進める
5. 継続テーマの会議を束ね、全体の流れを理解する
6. 保存先と外部処理の有無を把握し、安心して使う

## C. Information architecture

トップレベルはタブの4領域と、タブに載せない設定、どこからでも届く独立した追加アクションに絞る。

### ホーム

- 今日のダイジェスト（会議件数・未完了タスク・記録件数）と一日の時間分布
- Omiなどの短い記録を時間順に読むライフログのタイムライン
- 日常の記録だけを対象にした検索
- カレンダーから次の会議を表示し、その場で録音を開始（許可した場合のみ）
- 人をストーリー風の横スクロールで並べ、選ぶとその人にひもづく記録だけに絞り込める。写真も登録できる
- 接続中・未接続・同期待ちを示す外部レコーダー状態
- 会議に昇格した記録から元の議事録への導線
- 右上の＋からメモ・写真・イベント・場所を手動追加。場所は明示的な許可後に現在地付近の駅を候補化し、保存前に編集可能
- 右上の歯車から設定をモーダルで開く
- 左上のプロフィールボタンと画面左端のスワイプから、ファイルと同じライブラリのサイドバーを開く

ダイジェストの会議と未完了タスクはそのまま該当タブへ移動できる。ライフログは独立したタブを持たず、一日の流れを読む場所としてホームに統合する。

### ファイル

- ファイルの検索と一覧
- プロジェクトの検索と一覧
- 左サイドバーによる「ファイル／プロジェクト」の切り替え
- プロジェクト追加は共通の「＋」から開始し、ファイル画面内に重複する＋を置かない
- 開いている会話の文脈を保ったAI質問

Projectsは「管理対象」ではなく、関連する会話を束ねる軽量な**プロジェクト**としてファイル領域へ統合する。フォルダ分けを先に要求せず、必要になったユーザーだけが利用する。

### Ask AI

- タイトル・発言・決定・タスクを横断する通常検索
- 自然文によるAI検索
- File / Project / Globalの検索範囲
- 回答の根拠となった会議とタイムスタンプ
- 質問履歴

AIは独立したチャットアプリにせず、Ask AIによる横断検索と、会議一覧・詳細の下部composerによる文脈アクションとして配置する。

### タスク

- 複数会議から抽出された未完了タスク
- 会議に依存しない手入力タスク
- 担当者、期限、元の会議
- 完了済みの確認

### 設定（タブではなくモーダル）

設定は日々移動する場所ではないため、タブから外してホーム右上の歯車とファイルのサイドバーから開くモーダルにする。

- アカウントとSubscription
- 文字起こしエンジン（自動／Apple SpeechAnalyzer／端末内Whisper／クラウドBYOK）と言語
- AIエンジン（自動／Apple Foundation Models／ローカルLLM／クラウドBYOK）とプロバイダー・APIキー
- Omi・PLAUDなど外部レコーダーとの接続と音声取り込み
- ローカル保存とプライバシー
- ヘルプとデータ管理

タブはUISegmentedControlで描いたセグメントとしてガラスのカプセルに収め、その右にタブと同じ高さで視覚的に分離した「＋」を置く。押すと録音開始・音声インポート・オンライン会議キャプチャ・プロジェクト作成がポップオーバーで現れ、選ぶとその場で閉じて対応する処理へ進む。画面全体を覆うフロストは使わず、下の文脈とタブバーを見せたままにする。

## D. Main user flow

1. 初回起動で3ページの短いオンボーディングを見る。いつでもスキップでき、二度目以降は出ない
2. 「最初の会話を録音」を押した時にだけマイク権限を要求する。サインインも購入も要求しない
3. 録音中は下部シートへタイトル、ノート／文字起こし、一時停止、終了をまとめ、経過時間は上部へ、タイトルは切り替えタブの下へ置く。声に合わせて下端のグラデーションが反応し、記録が続いていることをさりげなく伝える
4. 画面を閉じても録音を継続し、Live Activityで状態を確認できる
5. 停止直後に音声をFileとして保存し、一覧と会議詳細へ即反映する
6. 外部音声のインポートは保存だけで止め、「文字起こしを開始」→「要約方法を選んで生成」を明示操作にする
7. 「音声を保存 → 文字にする → 要点と行動を整理」の進行を人間向けの言葉で表示する
8. 完成済みの文字起こしは、AI整理が未完了でも先に利用可能にする
9. 完了後は、サマリー → 決定 → 次の行動 → 未決事項 → 重要点の順に読む
10. 要約・文字起こし・ノートを同じ詳細画面で切り替え、必要なら下部からAIへ質問する
11. タスクは元の会議と結び付いたまま、横断タスク画面にも集約する
12. 最初の会話が整理されたあとに一度だけPlusを提案する。価値を見る前に価格を見せない
13. サインインは同期が欲しくなった時に、設定またはオンボーディング末尾から任意で行う

## E. Navigation

標準のTabViewを状態管理に使いながら、下部の明確なナビゲーションで「ホーム／ファイル／Ask AI／タスク」を切り替える。タブはシステム標準のセグメントコントロールとしてLiquid Glassのカプセルに収まり、選択中の面は標準のピルとして移動する。タブは場所の移動だけに使い、追加操作は右端の独立した「＋」へ分離する。「＋」はどの領域でも同じ場所にあり、録音開始・音声インポート・オンライン会議キャプチャ・プロジェクト作成の起点になる。

会議詳細はNavigationStackで深掘りし、録音セッション・追加方法の選択・サインイン・Paywall・AI回答は一時的で自己完結するためモーダル表示にする。どのタブでもナビゲーションの直上へ同じAI composerを固定し、質問範囲をGlobal / File / Projectへ自動で切り替える。会議詳細に入ったら進入元にかかわらず通常のタブバーを隠してcomposerだけを残し、戻る操作は常にNavigationStack上の1つ前へ戻す。Ask AIタブを選ぶとcomposerへフォーカスが移り、キーボードからそのまま質問できる。

ホームとファイルのプロフィールボタンと画面左端のスワイプは、画面幅の約82%を使うサイドバーを開く。開き具合はひとつの値だけで表し、ドラッグ・タップ・プログラムからの操作が同じ値を動かすので、途中で止まったり食い違ったりしない。サイドバーは本文よりわずかに遅れて追従し、手前の本文は等倍のまま右へスライドする。本文は明るさを落とさず、薄いブラーと影を加える。透明なタップ面または逆方向のドラッグで閉じる。詳細を開いている間はサイドバーを無効にし、画面左端はNavigationStackの戻る操作へ譲る。タブバーが素早い切り替えを担う一方で、サイドバーは全体を見渡す場所として、アカウント、トップレベルの移動、ライブラリの各セクションへの移動、最近のプロジェクトへの直接移動、外部レコーダーの接続状態を同じ一覧に収める。外部レコーダーの行は設定モーダルへつながる。

下部のタブバー・「＋」・composerはLiquid Glassの機能レイヤーとして扱い、コンテンツはその下を流れる。HIGに従いガラスはこの3つだけに限り、コンテンツ層は標準マテリアルのままにする。タブは統一したSF Symbolと短い名称を併記し、見ただけで移動先が分かるようにする。下へ読み進めるとバーと「＋」を退避させ、上へ戻すと先頭に着く前に復帰する。キーボードが出ている間はバーを退避させ、composerだけがキーボードの上に残る。

## F. Screen list

### Core flow

1. First launch / Value statement
2. Files / Meeting files
3. Recording session
4. Import picker and import progress
5. Processing meeting detail
6. Completed meeting detail
7. Partial-success meeting detail
8. Full transcript
9. Speaker correction
10. Contextual AI composer
11. AI answer with sources

### Retrieval and organization

12. Sidebar
13. Project list and creation
14. Life log timeline
15. All meetings
16. Unified search results
17. Project detail
18. Cross-meeting tasks

### Account and business

19. Settings
20. Speech recognition settings
21. AI settings / API key entry
22. Privacy and storage
23. Subscription / Paywall
24. Sign-in options
25. Email sign-up / log-in

### State coverage

26. Empty meeting files / projects / life log
27. Files and projects search with no results
28. Recording / paused / stopping
29. Life log disconnected / connected / waiting / sync error
30. Empty tasks
31. Empty AI history
32. Microphone denied / recording error
33. Import error
34. STT error and retry
35. AI-only failure with transcript preserved
36. Missing API key / network error
37. Signed-out / signed-in account
38. Free / subscribed plan

## G. High-fidelity UI

### First launch

記録・理解・行動の3ページに絞り、各ページへ成果を示す小さなプレビューを添える。スキップは常に出し、最終ページで「最初の会話を録音」「サンプルで見る」「アカウントで続ける」を提示する。ページ間で見出しやCTAの位置が動かないよう、レイアウトを固定する。

### Account

サインインは任意で、遅らせられる限り遅らせる。Apple / Google / メールアドレスの3方式を出し、メールは新規登録とログインを同じ画面でセグメント切り替えする。同期以外の機能はサインインなしで使えることを、サインイン画面自身に明記する。作成したアカウントは設定から削除できる。

### Paywall

最初の会話が整理された直後に一度だけ提示し、以降は設定から開く。年額・月額を切り替え、無料トライアルの条件を控えめな文字で明示する。購入後は同じ画面が利用中の状態へ切り替わる。

### Files

ヒーローカードやナビゲーションタイトルと重複する一覧見出しは置かず、左のサイドバーからファイルとプロジェクトを切り替える。ファイル画面は上部のセグメントで「ファイル／プロジェクト」を切り替える。人は連絡先から選ぶか新規作成し、会議詳細の「参加者」から記録にひもづける。ファイルは大きなカードで並べ、カードにはタイトル・要約・録音日時・長さ・処理状態を示す。カードは中立のグレー面に統一し、色で状態を語らない。押すとそのカードから詳細へズームでつながり、左へスワイプすると削除が現れる。プロジェクトは2列のフォルダ状タイルで並べ、直近の議事録アイコンと件数を示し、こちらもズームで詳細へつながる。サイドバーのライブラリ行は対応するセグメントへの移動として働く。追加は共通の「＋」へ集約し、ナビゲーションバーに重複する＋を置かない。

### Life log

会議やプロジェクトとは別の時間軸として、Omiなどから届く短い日常記録を並べる。最上段は件数・時間範囲・記録位置を示す一日のタイムラインとし、その下に種類別カードを置く。メモ・写真・イベント・場所を同じ時間軸へ追加できる。場所は利用者が操作した時だけ現在地を取得し、近くの駅または場所名を編集可能な候補として扱う。外部レコーダーの状態は一行へ静かに表示し、設定へ移動できる。接続は記録の転送完了を意味しないため、「接続中」と「新しい記録を待っています」を分けて伝える。

### Imported audio and AI cost

音声インポートはファイルコピー完了時点で「未処理」とし、文字起こしを自動開始しない。詳細画面で利用者が開始した時だけ文字起こしを行い、完成後も「要約待ち」で停止する。要約は自動構成または議事録・詳細議事録・アクション中心のテンプレートを選び、画面下部の「生成」を確定した時だけ実行する。各待機状態には「実行するまでAI利用は発生しません」と明示する。

### Recording session

録音は全画面の専用モードではなく、元の文脈が背後に残る高さ約50%のLiquid Glassシートにする。上部に経過時間と閉じるボタン、その下にノート／文字起こしの切り替え、切り替えの下にタイトル入力を置く。タイトルは録音中に変更でき、ノートへメモを残せる。文字起こしは録音後に入るため録音中は余白のままにし、代わりに下端のグラデーションが声に合わせて反応する。一時停止／再開と終了を最下段の同じ操作群へまとめ、Liquid Glassはこの操作群と閉じるボタンだけに使う。外観はアプリのライト／ダークに従う。

### Meeting detail

右上の共有から、要約・決定・次の行動をテキストにまとめてシステムの共有シートへ渡せる。MessagesやMail、Google Driveなど、端末に入っているアプリへそのまま共有できる。PDFでも書き出せ、Notionはインテグレーショントークン（BYOK）と保存先を設定するとページとして直接保存できる。共有リンク（memora://meeting/…）をコピーでき、受け取った人がMemoraを入れていればその会議を開ける。共有するテキストにもこのリンクを含める。

詳細は「サマリー／文字起こし／ノート」の3領域をセグメントで切り替える。見出しの下には記録にひもづく人を、Homeの並びと同じ丸いアバター（写真または頭文字＋名前）で横に並べ、末尾の丸い「追加」から足せる。サマリーは横幅を広く使い、左揃えの結論から「決まったこと」「次にすること」「まだ決まっていないこと」「重要なポイント」へ読み進める。切り替えは横滑りさせず、位置を保った短いフェードとスケールで連続性を守る。Reduce Motionではフェードだけにする。スクロール後はファイル名を上部へ引き継ぎ、文脈を失わせない。ノートは説明カードを置かない白いキャンバスとし、タップ入力と写真添付（保存され、あとから削除もできる）だけを提示する。生成された内容は、要約をタップするとその場で編集でき（Markdownを解釈した状態のまま、太字や斜体などの書式を保って直せる）、決まったこと・未決事項・重要なポイントも見出しまたは本文をタップして1行ずつのテキストへ直せる。「編集」ボタンは置かず、内容そのものを操作対象にする。モーダルの編集シートも置かず、読む画面のまま直して閉じれば保存される。編集が始まるとAsk AIの入力欄は隠れ、キーボードと本文が重ならない。タイトルは別途、会議名の変更から直せる。音声再生は今回の範囲から外し、情報の理解と活用に集中する。

### Transcript

各発言にタイムスタンプを残す。確度の低い話者には色だけでなく「？」を併記し、タップで修正できる。将来音声再生を戻す時に、タイムスタンプを音声位置へ結び付けられる情報構造を維持する。

### Ask

下部composerは、上部に広いテキスト面（「Ask Anything」）、下部に添付（クリップ）・使用するAIのチップ・音声／送信の丸ボタンをひとつのガラス面へまとめる。テキストが空のときは丸ボタンが音声入力になり、入力があると送信へ切り替わる。クリップは写真・音声・一般ファイルを選ぶ短いメニューを開き、AIチップは使用するモデルを切り替える。音声入力中は入力面を暗転させず、下端のグラデーションが声に合わせて反応する。Ask AI画面はチャット形式にする。人の発言は右の吹き出し、回答は左に置き、回答の根拠（思考）は「思考を表示」で折りたたむ。回答は単語ごとに小さなぼかしから現れるStreaming Textで表示する（Reduce Motionでは即時に表示）。回答中は考えていることを示し、空のときはサンプル質問を並べて下部のcomposerからそのまま会話を始められる。対象（すべて／ファイル／プロジェクト）は左上のメニューで選び、新しいチャットは右上で会話をやり直せる。通常検索と履歴も右上へ退避する。空白をタップするとキーボードを閉じる。会議の詳細から開く場合は従来どおりcomposerから回答シートを出し、根拠会議と時刻へ移動できる。

## H. Interaction

- 録音開始: 1タップ。権限要求は初回の文脈内だけ
- 録音停止: 大きな停止ボタン、ハプティック、即時保存
- 録音継続: 画面を閉じても継続し、会議画面のストリップとLive Activityから復帰
- 処理: 内容を即時作成し、段階表示。終わった成果物から開放
- インポート: Files picker → 端末保存 → 未処理 → 手動文字起こし → 手動要約
- 外部レコーダー: 設定の「デバイス」から接続し、利用可能な経路だけを明示して音声を取り込む
- タスク追加: 右上の＋からタイトル・担当・期限を入力し、会議に紐付かない行動も保存する
- AI入力: 写真・音声・Filesの添付とSpeechによる音声入力を同じcomposerから開始する
- キーボード: 編集中の入力欄以外をタップすると閉じる。シートやポップオーバーの中でも同じように働き、入力欄自身のタップでは閉じない。編集を始めた入力欄はキーボードが上がりきったあとに画面中央へ自動でスクロールし、本文が隠れない
- タスク完了: スプリングアニメーションで状態変更、元会議への導線を維持
- AI composer: ファイルではGlobal、詳細ではFileへ質問範囲を自動で合わせ、利用者には切り替えを意識させない
- AI: 質問送信中は状態に応じて呼吸するThinking Orbで根拠探索中を表現し、回答後にSourceを表示
- モーション: 画面遷移・コントロール・強調の3種類のスプリングに統一する。主要な見出し・サマリーは短いText Revealで読み始めを導き、AI回答は単語ごとにぼかしから現れるStreaming Textで読み始めを導く。一覧の各行や頻繁な操作には使わない。Reduce Motionでは移動・マスク・ぼかしを止めて即時に表示する
- Reduce MotionやDynamic Typeを壊さない標準コンテナとテキストスタイルを優先

## UI state stack

画面を「状態ごとの別デザイン」に分裂させず、次のレイヤーを同じ順序で重ねる。

1. **Canvas**: ファイル一覧、ライフログ、詳細本文など長く残る内容
2. **Context state**: 空、検索結果なし、処理中、部分成功、接続待ち
3. **Floating controls**: タブバー、Ask AI composer、録音中ストリップ
4. **Transient task**: ファイル追加、録音シート、認証、Paywall
5. **System interruption**: 権限、録音失敗、インポート失敗

Filesは「空／内容あり／検索中／結果なし」、Projectsは「空／内容あり／作成中」、Life logは「空／内容あり／未接続／接続中／同期待ち／失敗／手動追加」、Recordingは「開始準備／録音中／一時停止／終了処理／失敗」、Meetingは「読み込み／文字起こし待ち／文字起こし中／要約待ち／整理中／部分成功／完了」を最低限の状態集合とする。上のレイヤーが現れても下の文脈を破棄せず、閉じた時に元の位置へ戻れることを共通契約にする。

## I. Design system

### Typography

- Display: system Large Title Bold
- Screen title: system Large Title / Title Bold
- Section: Title 2 / Title 3 Bold
- Body: Body with increased line spacing for summaries and transcripts
- Metadata: Subheadline / Caption
- Duration: rounded, monospaced digits
- すべてDynamic Type対応。固定サイズは録音タイマーとブランドシンボルに限定

### Spacing

- Base unit: 4pt
- Inline: 6–12pt
- Component: 14–20pt
- Section: 28–30pt
- Screen horizontal inset: 18–24pt
- Primary corner radius: 16–26pt, hierarchyに応じて使用

### Material

- Functional layer（tab bar / 「＋」 / composer）: Liquid Glass regular。iOS 26未満は同形状のマテリアルへフォールバック
- Content layer: 標準マテリアルとsemantic backgroundのみ。ガラスは使わない
- 強調したい面（「＋」・送信）はガラスにtintを重ね、不透明な面として読ませる

### Color

- Canvas / grouped surfaces: iOS semantic system colors
- Primary action / intelligence: semantic Black（Dark ModeではWhiteへ反転）
- Recording / critical interruption: system Red
- Ambiguity / recoverable warning: system Orange
- 完了・決定・AIは色分けせず、黒・白・グレーとsymbolで意味を伝える
- 状態は色だけに依存せず、一覧では明瞭なtext、操作ではsymbolとアクセシビリティ名を使う

### Components

- Liquid Glass segmented tab bar, prominent capture button, and its popover
- Context-aware AI composer
- Native voice glow and Thinking Orb
- Siri-inspired recording wave and recording-edge beam
- File sidebar and project row
- Meeting row
- Processing steps
- Partial-success banner
- Insight section
- Provenance-aware task row
- Source link
- ContentUnavailableView-based empty state
- Form-based settings
- Onboarding page with outcome preview
- Provider and email authentication forms

### Iconography

意味を担うアイコンはSF Symbolsへ統一し、medium weightのアウトラインを基本に、選択・録音など状態を表す時だけfillを使う。コンテンツの先頭アイコンは同じ角丸バッジへ揃え、ラベルとアクセシビリティ名を付ける。録音=`waveform`、AI=`sparkles`、決定=`checkmark.seal`、タスク=`checkmark.square`、信頼=`lock.shield`を主語彙とする。

## Extension roles

- Widget: Home ScreenからMemoraの記録入口を思い出せる静的ショートカット
- Control: Control CenterからMemoraを即座に開く
- Live Activity: 録音中の経過時間と端末保存状態をLock Screen / Dynamic Islandで表示

Widgetはアプリを開いた時とタイムライン更新時に更新する。録音状態はLive Activityが担い、Widgetへ擬似リアルタイム状態を持たせない。

## Implementation boundary

このBitrigプロジェクトは、設計を操作検証できるSwiftUIリファレンス実装である。録音・一時停止・ファイルコピー・Live Activity・Ask AIの音声認識とファイル添付に加え、Omiは公開BLEサービスを使った検出と接続、PLAUDはFiles経由の音声取り込みが実動する。ホームのライフログは将来の音声同期を受け取る表示モデルとサンプルを持つが、Omiからの音声転送自体はまだ接続後の実装境界にある。PLAUD Embeddedによる直接接続は、開発者資格情報と実機専用SDKを組み込む段階まで「準備中」として区別する。文字起こしは、設定で選んだエンジンに応じてiOS 26以降のSpeechAnalyzer（端末内）を使い、利用できない場合はプレースホルダーの文字起こしへフォールバックする。AI回答も同様に、iOS 26以降のFoundation Modelsで端末内生成を試み、使えなければ定型回答へフォールバックする。クラウド（BYOK）は、キーチェーンに保存したAPIキーで、AI回答はOpenAI／Anthropic、文字起こしはOpenAI／Deepgramを実呼び出しする。端末内Whisper・ローカルLLMはモデルの同梱が必要なため未接続で、選ぶと端末内または定型へフォールバックする。会議のPDF出力と、Notionへのページ保存（インテグレーショントークンのBYOK）を実装する。GoogleドライブへのGoogleドキュメント作成はOAuthが必要なため、いまはPDFを共有シート経由でドライブへ保存する形にする。公開共有リンクの発行は次段階とする。オンライン会議キャプチャは処理状態を含むプロトタイプ体験として再現する。React Native + Expo本体へ移植する場合も、NavigationStack相当、bottom navigation、file picker、native recording bridge、ActivityKit bridgeへ分割可能な構成にしている。
