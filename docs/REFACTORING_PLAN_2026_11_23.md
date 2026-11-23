# Memora — 全体リファクタリング／改善調査 計画

調査日: 2026-11-23 / 対象: 1,396 Swift ファイル・約 103,000 行（`App/` 直下、平置き）

## 0. 調査結果の要約

コードベースは既に高い品質に整えられている。`ObservableObject` / `@Published` は 0 件、
`#Preview` / `PreviewProvider` は 0 件、`systemName` リテラルは 0 件、force unwrap は 8 件、
`fatalError` は 0 件。ビルドは警告 0 で成功する。`@Observable`（39 箇所）と
`assignIfChanged` による「変化した時だけ再描画」の仕組みは既に整備済み。

したがって本次は「全面書き直し」ではなく、**機能を減らさずに性能・保守性・一貫性を
取り戻す**ための限定的な整理を中心とする。

### 検証済みの事実（推測ではなくコードで確認済み）

| 主張 | 確認方法 | 結果 |
|---|---|---|
| in-place 配列変更で `didSet` が発火する | 最小 Swift スニペットで実行 | **発火する**（HIGH の前提が成立） |
| `projectTaskCounts` が未使用 | 全 1,396 ファイルから参照検索 | 定義と計算の 2 箇所ののみ = **死んだコード** |
| `isDetailComposerVisible` が未使用 | 全参照を確認 | `true` を代入する 2 箇所のみ、`false` なし = **死んだ状態** |
| `SpeechInputService` / `AudioPlayerService` が stopper を解除しない | 全 `registerStopper` 呼び出しを検査 | 他の 4 サービスは解除、**この 2 つだけ未解除** = **リーク** |
| `audioLevel` の高頻度更新がコンポーザーを再描画 | 読み取り箇所を全検索 | 読み手は `AIInputWaveform` のみ = **この主張は誤り。撤回** |
| `toolRegistry()` は 18 箇所から呼ばれ毎回再構築 | 全呼び出し箇所を列挙 | 24 ツールの JSON スキーマを毎回シリアライズ = **真实的** |
| 全 JSON を 1 行に格納 | `LocalStore.swift:58` を確認 | `documents(key, data BLOB)` のみ = **真实的** |

---

## 1. HIGH — 最優先（性能・リーク・正しさ）

### H1. `meetings.didSet` が 9 系統の副作用を全部叩く
**場所**: `App/MemoraModel.swift:73-90`

`meetings` の 1 要素を in-place で変更しても配列全体が置き換わり、`didSet` が発火する。
そこで以下が毎回走る。

- `invalidateSummaryArtifacts(previous:)` — 全レコードを Dictionary 化
- `MemoryRetrievalOrchestrator.invalidate()` — 検索インデックス破棄
- `meetingIndex.invalidate()`
- `meetingSearchTexts` の filter — 全件走査
- `rebuildMeetingAggregates()` — `meetings.sorted` + グループ化（O(n log n)）
- `refreshSampleContentFlag()`
- `invalidatePendingResidents()` / `invalidatePendingWebhookDeliveries()` / `invalidatePendingCloudShare()`

**最も悪いのは `updateMeetingTransiently`**（`App/MemoraModel+Meetings.swift:153`）。
「一時的」更新＝永続化しないという意図だが、副作用グラフは通常更新と区別されていない。
この関数の呼び出し元は 3 つ:

- `App/MemoraModel+SummaryGeneration.swift:141` — 要約の進捗表示（**ストリーミングごとに発火**）
- `App/MemoraModel+SummaryGeneration.swift:229` — 保存中ステータス
- `App/MemoraModel+Processing.swift:116` — 文字起こし進捗

つまり要約生成中・文字起こし中に、**進捗表示 1 回ごとに検索インデックス破棄＋集計再構築**が走る。

**対策**: 副作用を「構造的変更」と「一時的更新」で分離する。
- 一時的更新用の専用プロパティ（例 `transientMeetingStatuses: [UUID: MeetingStatus]`）を検討
- もしくは `didSet` の中で「実際に内容が変わったか」を判定し、無変化なら副作用をスキップ
- もしくは `updateMeetingTransiently` だけ副作用抑制フラグを立てる

**機能への影響**: なし（表示と永続化の挙動は同一に保てる）

### H2. `SpeechInputService` / `AudioPlayerService` の AudioSession stopper リーク
**場所**: `App/SpeechInputService.swift:27-33`, `App/AudioPlayerService.swift:55-62`

`AudioSessionCoordinator.registerStopper` は `UUID` を返すが、この 2 つは返り値を捨て、
`unregisterStopper` も呼ばない。他の 4 サービス（`VoiceEnrollmentService`, `LiveConversationSession`,
`SourceVideoPlayback`, `AnswerSpeechService`）は正しく解除している。

**影響**:
- `AIComposerBar` の `SpeechInputService` は `AIComposerBar` の identity ごとに生成される。
  `AIComposerBar` は通常表示・シート内・`RecordAIEditComposer` 内と複数箇所で生成・破棄される
  → stopper が積み上がる
- `MeetingDetailView` の `AudioPlayerService` も記録を開くたびに生成される
- `AudioSessionCoordinator.beginRecording()` は `stoppers` を全走査して await する
  → **録音開始時の停止処理がリーク量に比例して遅延する**

**対策**: `stopperID` を保持し `deinit` で `unregisterStopper` する。

**機能への影響**: なし（挙動は同じで、リークだけが消える）

### H3. `projectTaskCounts` が死んでいる
**場所**: `App/MemoraModel.swift:172`（宣言）, `:911-913`（計算）

全 1,396 ファイルから参照を検索した結果、定義と計算の 2 箇所のみ。
しかも `rebuildMeetingAggregates()` の先頭で毎回計算されるため、H1 の影響を受ける。
**対策**: 削除する（`rebuildProjectTaskCounts()` ごと）。

### H4. `isDetailComposerVisible` が死んでいる
**場所**: `App/MemoraModel.swift:465`, `App/MeetingDetailView.swift:126,165`, `App/RootTabView.swift:420,628`

`true` を代入する 2 箇所のみ。`false` にする箇所は 1 つも存在しない。
`RootTabView.shouldShowComposer` がこれを判定材料にしているが、常に `true` なので
「記録詳細は明示的にコンポーザーに余地を作る」分岐が機能していない。

**注意**: `App/MemoraModel.swift:463-464` のコメントに「詳細で文書を移動する時はコンポーザーを隠す」意図の
記載がある。**削除ではなく、意図された挙動を実装する**べき。
**要確認**: 記録詳細での文書移動（document move）時にコンポーザーを隠す挙動が必要か。

**対策**: 意図を実装するか、無意味なら削除して `shouldShowComposer` を単純化する。

### H5. `LocalStore` が全レコードを一つの BLOB 行に格納
**場所**: `App/LocalStore.swift:58-62`

```sql
CREATE TABLE IF NOT EXISTS documents (key TEXT PRIMARY KEY, data BLOB NOT NULL, updated_at REAL NOT NULL);
```

`meetings` は `StorageKey.meetings` の 1 キーに `[Meeting]` 配列全体を JSON として保存する。
1 件の要約更新で **全レコードの配列を書き直す**。`tasks` / `documents` / `lifeLogEntries` も同じ。

**影響**: スケーラビリティの上限が「総バイト数」で決まる。1000 件規模では 1 回の保存で
数百 KB の JSON をエンコードし直す。

**対策**: 実 Tables への分割（`meetings` / `tasks` / `life_log_entries` / `documents` / `projects`）。
ただし **移行戦略が必要**で、これは本計画の中核的変更。
段階案:
1. 既存の単一 BLOB はそのまま読む（後方互換）
2. 新しい行単位テーブルを追加し、書き込む先を切り替え
3. 起動時に 1 回だけ移行（冪等）

**機能への影響**: なし（読み書きの API は同じ形を保つ）
**リスク**: MEDIUM。移行と復旧（バックアップからの復元）の検証が必要。
**代替案**: 段階を踏まず「1 件の更新は `meetings` 全体を書き直す」のままでも、
H1 の副作用分離と H6 の非同期化だけでも体感は大きく変わる。

### H6. `RecordStore.commitNow` がメインスレッドをブロック
**場所**: `App/RecordStore.swift:225-238`

`RecordStore` は `@MainActor` で、`queue.sync` により SQLite 書き込みを待つ。
**62 箇所の `persistNow(` / `commitNow(` が同期版を使っている**（非同期版は 7 箇所のみ）。

**影響**: 1 件の要約保存で、JSON エンコード（現在 `Task.detached` 済み）＋SQLite 書き込みが
メインスレッドをブロックする。

**対策**: UI 経路では `persistBatchAsync` / `commitAsync` を使う。
ただし**順序保証**が必要（保存失敗時にUNDOを保持する設計がある）ため、
`+Meetings.swift:88-123` の rebase 付き非同期版と統一する方向で進める。

**注意**: 順序と失敗処理の不変条件は AGENTS.md / `docs/MEETING_SAVE_FIXES_2026_11_10.md` に
記録がある。**機械的な一括置換はしない**。

---

## 2. MEDIUM — 実施価値が高い

### M1. `toolRegistry()` が呼び出しごとに全ツールを再構築
**場所**: `App/MemoraModel+ToolExecution.swift:18-32`

24 ツールの `inputSchema` を `JSONSerialization` で毎回シリアライズし、`AIToolRegistry` を
ゼロから作る。**18 箇所**から呼ばれ、エージェント 1 ターンに複数回呼ばれる。
`enabledAgentTools` 自体も毎回 `AgentTool.offered` を走査する。

**対策**: 有効なツール構成が変わったときだけ再構築し、キャッシュする。
キーは `enabledAgentTools` の内容 + `activeMCPTools` の内容 + MCP サーバー設定の組合せ。

### M2. `allSummaryChoices` が呼び出しごとにカタログを再構築
**場所**: `App/MemoraModel+Personalization.swift:34-42`

`builtInChoices + customTemplates + SummaryTemplateCatalog.market` を毎回連結し、
`summaryChoice(_:)` は `first` で走査する。6 箇所から呼ばれる。

**対策**: `assignIfChanged` でキャッシュ。

### M3. `sendAgentChat()` 301 行 / `generateSummary()` 279 行
**場所**: `App/MemoraModel+Agent.swift:15`, `App/MemoraModel+SummaryGeneration.swift:12`

どちらも「認可 → ストリーミング → 承認カード → 予算管理 → 記録」の複数関心事を持つ。
`performAgentTool()` の 25 ケース switch（`+AgentTools.swift:69-115`）も大きい。

**対策**: 関心事ごとに私有メソッドへ分割する。**振る舞いは変えない**。
引数の受け渡し增多打磨があるため、段階的に行う。

### M4. シートの閉じるボタンが 36 箇所で重複
**場所**: たとえば `App/AIChatModelSheet.swift:32`, `App/SettingsView.swift:71` など

すべて同一パターン `ToolbarItem(placement: .cancellationAction) { ToolbarIconButton("閉じる", icon: .xmark) { dismiss() } }`。
ただし `App/MarketplaceDetailSheet.swift:16` と `App/CommunityPostDetailView.swift:56` だけ
`.chevronLeft` で**見た目が違う**（表示の不整合）。

**対策**: `SheetCloseButton` 共通コンポーネントを作り、2 箇所の不整合も揃える。

### M5. `sourceHeader` / `excerptRow` が 2 ファイルで重複
**場所**: `App/AIQuestionView.swift:240-265`, `App/AIMessageView.swift:224-249`

同一データ型 `AIChatSource` に対するほぼ同一の実装。アイコンとサイズだけが違う。
`sourceAccessibilityLabel` も 2 箇所で**読み上げ文言が微妙に異なる**（VoiceOver の不整合）。

**対策**: `AISourceHeader` / `AISourceExcerptRow` に抽出して共通化。

### M6. `DocumentsView` と `PeopleView` が構造的に同一
**場所**: `App/DocumentsView.swift:22-58`, `App/PeopleView.swift:19-68`

`MemoraList` → `contentMargins` → `.overlay { CollectionSearchState / MemoraEmptyState }` →
`navigationTitle` → `toolbarSearch` → `onChange` → `.sheet` の並びが完全一致。

**対策**: 共通テンプレート（`SearchableCollectionList` のような）に抽出。

### M7. `index` ベースの `ForEach` id
**場所**: `App/AIQuestionView.swift:208`, `App/AIMessageView.swift:201`,
`App/AgentQuestionCard.swift:22`, `App/AgentQuestionCard.swift:63` ほか 16 箇所

`id: \.offset` は挿入・削除時に行が再利用され、VoiceOver のフォーカスがずれる。
**対策**: 対象データに安定した `id` を持たせる。識別子を持たせられないものは
`\.offset` を残す（静的リストなので実害がないものもある）。

### M8. `Task { }` の `self` 強捕捉 30 箇所（モデル層）
**場所**: `App/MemoraModel+Documents.swift:66`, `+Residents.swift:106,319`,
`+MCP.swift:22,37,45,47` ほか

`Task { }` は `self` を強捕捉するため、タスク完了までモデル（と全データ）が保持される。
**対策**: `[weak self]` を付ける。長いタスク（常駐エージェント、バックグラウンド要約）は特に重要。

---

## 3. LOW — 構造の整理 / 一貫性

### L1. `DocumentsView` / `PeopleView` の `List` + `ScrollView` 混在
`List` の `.overlay` 内に `ScrollView` があってスクロールビューが 2 個存在する。
技術的には回避されているが、空状態の実装が 5 箇所で重複（`MemoraEmptyState` の重複）。

### L2. `SettingsCategoryView` の 12 カテゴリが 1 ファイルに
`App/SettingsCategoryView.swift:36-50` の switch が 10 個の computed property
（415 行）を呼ぶ。カテゴリごとに別ファイルへ抽出できる。

### L3. `GeometryReader` が 13 箇所
`App/JournalTimelineRow.swift:26` は `LazyVStack` の行ごとに置かれるため、
行数に比例してレイアウトコストが上がる。`Canvas` や `Shape` に置き換え可能。

### L4. `RootTabView` に `.animation` が 8 個集中
`App/RootTabView.swift:417-426`。`bottomControls` 全体に効くため、
外部フラグ（`model.isInlineEditing` 等）の変化でガラスEphIZANumもアニメーション対象になる。
AGENTS.md は「remove their visual menus without animation while composing」と指示しているため、
スコープを `.overlay` / `.transition` の局所へ移すべき。

### L5. `ComposerInputObserver` の 0.12 秒タイマー
`App/ComposerInputObserver.swift:44`。`state.value` の更新は `@Observable` なので、
入力中は 0.12 秒ごとに `QuickAIComposer` が再評価される。
ただし**入力欄の生の値は別の TextField バインディング**で持っており、
差分は 0.12 秒ごとにしか反映されない = **IME 入力の遅延の原因**。

### L6. `model.askAIConfiguration` はタプル computed property
`App/MemoraModel+ModelSelection.swift:10-15`。Observation で追跡できないため、
`onChange(of: model.askAIConfiguration.engine)` は発火しない（または意図せず発火する）。
AGENTS.md は「Both Ask AI paths capture `askAIConfiguration` once per question」と
指示しているので、UI 側で `onChange` 監視する必要自体がない。

### L7. `MeetingDetailView` の `onDisappear` が 2 つ
`App/MeetingDetailView.swift:144-151` と `:163-166`。SwiftUI は両方を呼ぶため、
副作用の順序に依存する fragile な構造。1 つに統合。

---

## 4. 実施しないこと（判断）

以下は**今回は行わない**。いずれも「機能を減らす」 risking ではなく、
**リスクに対して効果が小さい**か、**別の作業的前提**が必要なため。

| 項目 | 判断理由 |
|---|---|
| `App/` をサブディレクトリに分割 | 1,396 ファイルの一括移動は Xcode プロジェクトへの反映と差分_reviews が巨大。**効果に対してリスクが大きすぎる**。 |
| `LocalStore` の行単位テーブル化 (H5) の全面実施 | 移行と復旧の検証負荷が大きい。**まず H1/H6 を完了してから**別計画で扱う |
| `sendAgentChat` の全面分割 (M3) | 300 行の分割は段階分割が必要。まず小さいメソッドから |
| `LibraryView.fileSections` の `O(n²)` | 実データが数百件以下なら体感しない。`firstIndex` 走査は実害小 |
| `ProjectSuggestionCard` の `O(spaces × meetings)` | 同様。数件なら問題なし |
| `#Preview` の追加 | AGENTS.md が明確に禁止 |
| テストの追加 | Project.json に test target が無い。`SelfChecks.swift` が代替 |
| 40 箇所の `id: \.offset` を全て排除 | 静的なリストへの過剰適用は可読性を下げる |
| `LocalStore` の prepared statement キャッシュ | **既に実装済み**（`App/LocalStore.swift:205-215`）。対象外 |

---

## 5. 実施順序（フェーズ）

各フェーズは独立してビルド可能・検証可能にする。**フェーズ完了ごとに
`bitrig preview -platform iOS` を実行して表示を確認する**。

### Phase 1: リークと死んだコードの解消（低リスク・効果確実）
- [x] **H2**: `SpeechInputService` / `AudioPlayerService` の stopper 解除
- [x] **H3**: `projectTaskCounts` の削除
- [ ] **H4**: `isDetailComposerVisible` の扱い決定（実装 or 削除）
- [x] **M8**: モデル層の `Task { }` の `[weak self]`（長命な常駐エージェント実行のみ。他はタスクの所有権管理があり意図的な保持のため対象外）
- [ ] **M4**: `SheetCloseButton` 共通化（2 箇所の不整合も修正）
- [ ] 検証: ビルド成功、`SelfChecks` 実行、録音→停止→録音の再繰り返しで stopper が貯まらないことを確認

### Phase 2: 一時更新の副作用分離（性能の中核）
- [x] **H1**: `meetings.didSet` の副作用を構造的変更と一時的更新で分離
- [ ] 検証: 要約生成・文字起こしの進捗表示中に、FTS インデックスが
      破棄されないことをデバッグ計測で確認。**画面表示は一切変えない**

### Phase 3: 派生値のキャッシュ
- [x] **M1**: `toolRegistry()` のキャッシュ
- [x] **M2**: `allSummaryChoices` のキャッシュ
- [x] `recordAccessRevision(for:)` のキャッシュ検討 → **.keyの構築自体が元の計算と同コスト**（全件走査+フィルタ+ソート+hashing）のため効果なし。スキップ
- [ ] 検証: エージェント 1 ターンの `toolRegistry()` 呼び出し回数が減ることを計測

### Phase 4: ility の一貫性（挙動不変の整理）
- [ ] **M5**: `AISourceHeader` / `AISourceExcerptRow` の抽出
- [ ] **M6**: `DocumentsView` / `PeopleView` の共通テンプレート化
- [ ] **M7**: `id: \.offset` のうち、動的に変わるものだけ安定 id に
- [ ] **L7**: `MeetingDetailView` の `onDisappear` 統合
- [ ] **L4**: `RootTabView` の `.animation` スコープを局所化
- [ ] 検証: ビルド成功。**UI の見た目が変わっていないことをスクリーンショット比較で確認**

### Phase 5: 大きな関数の分割（任意・時間 permitting）
- [ ] **M3**: `sendAgentChat()` / `generateSummary()` の分割
- [ ] **M2**: `SettingsCategoryView` のカテゴリ別ファイル化
- [ ] 検証: ビルド成功、`SelfChecks` 全通過

### Phase 6: 永続化（別計画として扱う）
- [ ] **H5**: `LocalStore` の行単位テーブル化
- [ ] **H6**: `commitNow` → 非同期化
- [ ] 移行・復旧・バックアップの検証を完備

---

## 6. 検証方法

| 項目 | 方法 |
|---|---|
| ビルド | `bitrig build -destination "generic/platform=iOS Simulator"`（現状: 成功・警告 0） |
| 自動チェック | `App/SelfChecks.swift`（DEBUG ビルドで `App.swift:25` から実行、`SelfChecks.results` に結果） |
| E2E | `tests/` に 68 個の e2e ファイル（`.e2e.ts`）、`e2e.config.ts` |
| 表示確認 | `bitrig preview -platform iOS`（AGENTS.md の作業規約に従う） |
| 効果計測 | フェーズ 2 / 3 では、DEBUG ビルドに一時的な計測を仕込み、Phase 完了時に外す |

**注意**: AGENTS.md により、`bitrig preview` は「アプリに影響する変更を完了したとき」に
実行する。フェーズごとに実行して表示を確認すること。

---

## 7. リスクと注意

1. **AGENTS.md の「既知の退行」リストを壊さない**
   ナビゲーション、作成コントロール、下端のフッター、検索、マーケットプレイス、タスク、
   共有表示、記録の読み方、プロジェクト文脈、ジャーナル、プロジェクトワークスペースの
   12 項目。Phase 4（UI 整理）で特に注意。

2. **`SelfChecks` は「失敗しても印刷するだけ」で、証明ではない**
   docs の記述どおり。機械的なチェックとしては使用しない。

3. **UI の見た目は変えてはならない**
   本計画は純粋な内部整理。画面・文言・導線は 1 つも変えない。
   視覚的な変更が必要なものは本計画外。

4. **H1 は注意が必要**
   `didSet` の副作用を分けると、検索インデックスの寿命が変わる。
   AGENTS.md の「記録検索」の挙動が変わらないことを実機確認する。

5. **H4 は機能判断が要る**
   「詳細で文書を移動時にコンポーザーを隠す」が意図だったなら実装が必要。
   意図じゃなければ削除。**どちらに倒しても既存の画面表示は変わらない**ので、
   どちらかに倒すだけでよい。**どちらに倒すかは先に確認する。**

---

## 8. この調査で見つかった「改善点」（機能追加ではなく品質）

コードベースは既に高品質。以下は**残存する**改善余地:

- **テスト基盤がない**: `Project.json` に test target が無い。`SelfChecks.swift`（2,330 行）が
  代替として機能しているが、DEBUG ビルドでしか動かず、失敗しても停止しない。
  **Xcode プロジェクトへの変換**（`bitrig convert-to-xcode-project`）=test target を
  追加できる。CI スイートを作れる。这是最大の改善余地。
- **CI は手動実行のみ**: `.github/workflows/quality.yml` は GitHub Actions の予算上限により
  `workflow_dispatch` 専用。ホスト品質チェックと 65 presentation レイアウト検査は
  整備されているが、自動では走らない。予算回復後の再有効化が課題。
- **`App/` が 1,396 ファイル平置き**: ファイル名検索はできるが、関連コードのiscoveryは目視のみ。
  サブディレクトリ分割は**リスクが高い**ため見送り推奨（§4）。
- **`docs/` が 100 以上のドキュメント**: 古いドキュメントの削除・統合の余地。
- **ツールレジストリの再構築**（M1）: エージェント 1 ターンあたり 18 回再構築。
- **`SelfChecks.swift` が 2,330 行**: 本身就是リファクタリング対象（機能領域別ファイルに）。
