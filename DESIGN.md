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

トップレベルは3領域に絞る。

### 会議

- 最優先の録音開始
- 音声インポート
- 最近の会話
- すべての会話
- スペース

Projectsは「管理対象」ではなく、関連する会話を束ねる軽量な**スペース**として会議ライブラリへ統合する。フォルダ分けを先に要求せず、必要になったユーザーだけが利用する。

### 探す

- タイトル・発言・決定・タスクを横断する通常検索
- 自然文によるAI検索
- File / Space / Globalの検索範囲
- 回答の根拠となった会議とタイムスタンプ
- 質問履歴

AIは独立したチャットアプリにせず、「探す」の拡張と会議詳細の文脈アクションとして配置する。

### タスク

- 複数会議から抽出された未完了タスク
- 担当者、期限、元の会議
- 完了済みの確認

設定は利用頻度が低いためタブにせず、各トップレベル画面のツールバーから開く。

## D. Main user flow

1. 初回起動で「話せば、次にすることまで残る」と価値を一文で理解する
2. 「最初の会話を録音」を押した時にだけマイク権限を要求する
3. 録音中は、経過時間・波形・端末保存中であること・停止操作だけを強調する
4. 画面を閉じても録音を継続し、Live Activityで状態を確認できる
5. 停止直後に音声をFileとして保存し、一覧と会議詳細へ即反映する
6. 「音声を保存 → 文字にする → 要点と行動を整理」の進行を人間向けの言葉で表示する
7. 完成済みの文字起こしは、AI整理が未完了でも先に利用可能にする
8. 完了後は、概要 → 決定 → 次の行動 → 未決事項 → 重要点の順に読む
9. 必要な時だけ全文文字起こし、音声、AI質問へ進む
10. タスクは元の会議と結び付いたまま、横断タスク画面にも集約する

## E. Navigation

標準のTabViewで「会議／探す／タスク」を常に切り替えられる。タブは場所の移動にだけ使い、録音開始をタブ項目や中央FABにはしない。録音は会議画面の最初の内容として、片手で届きやすい大きなアクション面に置く。

会議詳細はNavigationStackで深掘りし、録音セッションとAI質問は一時的で自己完結するためモーダル表示にする。これは、主要領域を少なく保ち、タブをアクションに使わないという[AppleのiOS設計](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)と[Tab barガイダンス](https://developer.apple.com/design/human-interface-guidelines/tab-bars)にも沿う。

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
10. Audio player
11. Contextual AI question
12. AI answer with sources

### Retrieval and organization

13. All meetings
14. Unified search results
15. Space detail
16. Cross-meeting tasks

### Account and business

17. Settings
18. Speech recognition settings
19. AI settings / API key entry
20. Privacy and storage
21. Subscription / Paywall

### State coverage

22. Empty meetings
23. Empty tasks
24. Empty AI history
25. Microphone denied / recording error
26. Import error
27. STT error and retry
28. AI-only failure with transcript preserved
29. Missing API key / network error

## G. High-fidelity UI

### First launch

説明カルーセルを廃止し、価値の一文、Record → Understand → Actの短い図、録音CTA、サンプル導線だけで構成する。サインインや購入は要求しない。

### Meetings

大きなインディゴのCapture surfaceを一つだけ置き、その下は軽いスペースピルと罫線ベースの会議一覧にする。カードを反復せず、タイトル・日時・長さ・処理状態を一目で走査できる。

### Meeting detail

音声・文字起こし・要約・AIを同列タブに分けない。最初のスクロール面は「一目でわかる」「決まったこと」「次にすること」「まだ決まっていないこと」「重要なポイント」の読み順とし、全文と音声は二次レイヤーに置く。

### Transcript

タイムスタンプを再生位置へのリンクとして扱い、再生中の発言を背景で示す。確度の低い話者には色だけでなく「？」を併記し、タップで修正できる。

### Ask

質問はFile / Space / Globalの範囲を明示する。回答直下に根拠会議と時刻を表示し、文字起こしへ移動できる。

## H. Interaction

- 録音開始: 1タップ。権限要求は初回の文脈内だけ
- 録音停止: 大きな停止ボタン、ハプティック、即時保存
- 録音継続: 画面を閉じても継続し、会議画面のストリップとLive Activityから復帰
- 処理: 内容を即時作成し、段階表示。終わった成果物から開放
- インポート: Files picker → 進捗 → 会議詳細 → 自動処理
- タスク完了: スプリングアニメーションで状態変更、元会議への導線を維持
- 音声: Play/Pause、連続シーク、現在時刻、総時間。全文側では発言追従
- AI: 質問送信中は根拠探索中と表現し、回答後にSourceを表示
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

### Color

- Canvas / grouped surfaces: iOS semantic system colors
- Primary action / intelligence: system Indigo
- Recording / critical interruption: system Red
- Decision / complete: system Green
- Ambiguity / recoverable warning: system Orange
- 状態は色だけに依存せず、必ずsymbolとtextを併記

### Components

- Capture surface
- Meeting row
- Processing steps
- Partial-success banner
- Insight section
- Provenance-aware task row
- Audio player bar
- Source link
- ContentUnavailableView-based empty state
- Form-based settings

### Iconography

SF Symbolsのみを用い、ラベルとアクセシビリティ名を付ける。録音=`waveform`、AI=`sparkles`、決定=`checkmark.seal.fill`、タスク=`checkmark.square`、信頼=`lock.shield`を主語彙とする。

## Extension roles

- Widget: Home ScreenからMemoraの記録入口を思い出せる静的ショートカット
- Control: Control CenterからMemoraを即座に開く
- Live Activity: 録音中の経過時間と端末保存状態をLock Screen / Dynamic Islandで表示

Widgetはアプリを開いた時とタイムライン更新時に更新する。録音状態はLive Activityが担い、Widgetへ擬似リアルタイム状態を持たせない。

## Implementation boundary

このBitrigプロジェクトは、設計を操作検証できるSwiftUIリファレンス実装である。録音・ファイルコピー・AVAudioEngine再生・Live Activityは実動し、文字起こしとAI回答は処理状態を含むデモデータで再現する。React Native + Expo本体へ移植する場合も、NavigationStack相当、native tab bar、file picker、native recording bridge、ActivityKit bridgeへ分割可能な構成にしている。
