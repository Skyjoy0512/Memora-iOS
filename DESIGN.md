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

トップレベルは4領域と、どこからでも届く独立した追加アクションに絞る。

### 会議

- 最近の会話
- すべての会話
- プロジェクト
- 会議文脈を保ったQuick AI / AI Chat

Projectsは「管理対象」ではなく、関連する会話を束ねる軽量な**プロジェクト**として会議ライブラリへ統合する。フォルダ分けを先に要求せず、必要になったユーザーだけが利用する。

### Ask AI

- タイトル・発言・決定・タスクを横断する通常検索
- 自然文によるAI検索
- File / Project / Globalの検索範囲
- 回答の根拠となった会議とタイムスタンプ
- 質問履歴

AIは独立したチャットアプリにせず、Ask AIによる横断検索と、会議一覧・詳細の下部composerによる文脈アクションとして配置する。

### タスク

- 複数会議から抽出された未完了タスク
- 担当者、期限、元の会議
- 完了済みの確認

### 設定

- アカウントとSubscription
- 文字起こし・AIの高度な設定
- ローカル保存とプライバシー
- ヘルプとデータ管理

右端にはタブと視覚的に分離した「＋」を置く。押すと録音開始・音声インポート・オンライン会議キャプチャを選択できる。

## D. Main user flow

1. 初回起動で3ページの短いオンボーディングを見る。いつでもスキップでき、二度目以降は出ない
2. 「最初の会話を録音」を押した時にだけマイク権限を要求する。サインインも購入も要求しない
3. 録音中は、経過時間・波形・端末保存中であること・停止操作だけを強調する
4. 画面を閉じても録音を継続し、Live Activityで状態を確認できる
5. 停止直後に音声をFileとして保存し、一覧と会議詳細へ即反映する
6. 「音声を保存 → 文字にする → 要点と行動を整理」の進行を人間向けの言葉で表示する
7. 完成済みの文字起こしは、AI整理が未完了でも先に利用可能にする
8. 完了後は、サマリー → 決定 → 次の行動 → 未決事項 → 重要点の順に読む
9. 要約・文字起こし・ノートを同じ詳細画面で切り替え、必要なら下部からAIへ質問する
10. タスクは元の会議と結び付いたまま、横断タスク画面にも集約する
11. 最初の会話が整理されたあとに一度だけPlusを提案する。価値を見る前に価格を見せない
12. サインインは同期が欲しくなった時に、設定またはオンボーディング末尾から任意で行う

## E. Navigation

標準のTabViewを状態管理に使いながら、下部の明確なナビゲーションで「会議／Ask AI／タスク／設定」を常に切り替える。タブは場所の移動だけに使い、追加操作は右端の独立した円形FABへ分離する。FABはどの領域でも同じ場所にあり、録音開始・音声インポート・オンライン会議キャプチャの起点になる。

会議詳細はNavigationStackで深掘りし、録音セッション・追加方法の選択・サインイン・Paywall・AI回答は一時的で自己完結するためモーダル表示にする。会議一覧と詳細では、ナビゲーションの直上へQuick AI / AI Chat composerを固定し、スコープをGlobal / Fileへ自動で切り替える。

下部のバー・FAB・composerはLiquid Glassの機能レイヤーとして扱い、コンテンツはその下を流れる。HIGに従いガラスはこの3つだけに限り、コンテンツ層は標準マテリアルのままにする。キーボードが出ている間はバーを退避させ、composerだけがキーボードの上に残る。

## F. Screen list

### Core flow

1. First launch / Value statement
2. Meetings / Library
3. Recording session
4. Import picker and import progress
5. Processing meeting detail
6. Completed meeting detail
7. Partial-success meeting detail
8. Full transcript
9. Speaker correction
10. Contextual Quick AI / AI Chat composer
11. AI answer with sources

### Retrieval and organization

12. All meetings
13. Unified search results
14. Project detail
15. Cross-meeting tasks

### Account and business

16. Settings
17. Speech recognition settings
18. AI settings / API key entry
19. Privacy and storage
20. Subscription / Paywall
21. Sign-in options
22. Email sign-up / log-in

### State coverage

23. Empty meetings
24. Empty tasks
25. Empty AI history
26. Microphone denied / recording error
27. Import error
28. STT error and retry
29. AI-only failure with transcript preserved
30. Missing API key / network error
31. Signed-out / signed-in account
32. Free / subscribed plan

## G. High-fidelity UI

### First launch

記録・理解・行動の3ページに絞り、各ページへ成果を示す小さなプレビューを添える。スキップは常に出し、最終ページで「最初の会話を録音」「サンプルで見る」「アカウントで続ける」を提示する。ページ間で見出しやCTAの位置が動かないよう、レイアウトを固定する。

### Account

サインインは任意で、遅らせられる限り遅らせる。Apple / Google / メールアドレスの3方式を出し、メールは新規登録とログインを同じ画面でセグメント切り替えする。同期以外の機能はサインインなしで使えることを、サインイン画面自身に明記する。作成したアカウントは設定から削除できる。

### Paywall

最初の会話が整理された直後に一度だけ提示し、以降は設定から開く。年額・月額を切り替え、無料トライアルの条件を控えめな文字で明示する。購入後は同じ画面が利用中の状態へ切り替わる。

### Meetings

ヒーローカードは置かず、画面を開いた直後からプロジェクトと罫線ベースの会議一覧を表示する。整理済みの行にはサマリーを最大3行表示し、タイトル・内容・日時・長さ・処理状態を一覧だけで走査できる。追加操作は右下の＋に集約する。

### Meeting detail

詳細は「要約／文字起こし／ノート」の3領域をセグメントで切り替える。要約では「サマリー」「決まったこと」「次にすること」「まだ決まっていないこと」「重要なポイント」の読み順を保つ。音声再生は今回の範囲から外し、情報の理解と活用に集中する。

### Transcript

各発言にタイムスタンプを残す。確度の低い話者には色だけでなく「？」を併記し、タップで修正できる。将来音声再生を戻す時に、タイムスタンプを音声位置へ結び付けられる情報構造を維持する。

### Ask

質問はFile / Project / Globalの範囲を明示する。下部composerはQuick AI / AI Chatの切り替えと入力に絞り、モデル選択は置かない。空いた場所は入力欄に回す。マイクからの音声入力も同じ行から始められ、キーボード表示中はその位置がキーボードを閉じる操作になる。回答直下に根拠会議と時刻を表示し、文字起こしへ移動できる。

## H. Interaction

- 録音開始: 1タップ。権限要求は初回の文脈内だけ
- 録音停止: 大きな停止ボタン、ハプティック、即時保存
- 録音継続: 画面を閉じても継続し、会議画面のストリップとLive Activityから復帰
- 処理: 内容を即時作成し、段階表示。終わった成果物から開放
- インポート: Files picker → 進捗 → 会議詳細 → 自動処理
- タスク完了: スプリングアニメーションで状態変更、元会議への導線を維持
- AI composer: 会議一覧ではGlobal、詳細ではFileへ自動でスコープを合わせ、モードと音声入力をその場で選択
- AI: 質問送信中は根拠探索中と表現し、回答後にSourceを表示
- モーション: 画面遷移・コントロール・強調の3種類のスプリングに統一し、Reduce Motionでは移動を止めて不透明度だけを変える
- Reduce MotionやDynamic Typeを壊さない標準コンテナとテキストスタイルを優先

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

- Functional layer（bottom bar / FAB / composer）: Liquid Glass regular。iOS 26未満は同形状のマテリアルへフォールバック
- Content layer: 標準マテリアルとsemantic backgroundのみ。ガラスは使わない
- 強調したい面（FAB・送信）はガラスにtintを重ね、不透明な面として読ませる

### Color

- Canvas / grouped surfaces: iOS semantic system colors
- Primary action / intelligence: semantic Black（Dark ModeではWhiteへ反転）
- Recording / critical interruption: system Red
- Ambiguity / recoverable warning: system Orange
- 完了・決定・AIは色分けせず、黒・白・グレーとsymbolで意味を伝える
- 状態は色だけに依存せず、必ずsymbolとtextを併記

### Components

- Liquid Glass bottom bar, capture FAB, and source picker
- Quick AI / AI Chat composer
- Compact project chip
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

SF Symbolsのみを用い、ラベルとアクセシビリティ名を付ける。録音=`waveform`、AI=`sparkles`、決定=`checkmark.seal.fill`、タスク=`checkmark.square`、信頼=`lock.shield`を主語彙とする。

## Extension roles

- Widget: Home ScreenからMemoraの記録入口を思い出せる静的ショートカット
- Control: Control CenterからMemoraを即座に開く
- Live Activity: 録音中の経過時間と端末保存状態をLock Screen / Dynamic Islandで表示

Widgetはアプリを開いた時とタイムライン更新時に更新する。録音状態はLive Activityが担い、Widgetへ擬似リアルタイム状態を持たせない。

## Implementation boundary

このBitrigプロジェクトは、設計を操作検証できるSwiftUIリファレンス実装である。録音・ファイルコピー・Live Activityは実動し、文字起こし・音声入力・AI回答・オンライン会議キャプチャは処理状態を含むプロトタイプ体験として再現する。React Native + Expo本体へ移植する場合も、NavigationStack相当、bottom navigation、file picker、native recording bridge、ActivityKit bridgeへ分割可能な構成にしている。
