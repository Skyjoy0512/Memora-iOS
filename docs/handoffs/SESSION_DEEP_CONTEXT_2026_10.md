# セッション引き継ぎ: 深い文脈・資料品質・モデル別コンテキスト

作成: 2026-10-30。別エージェントによる改善余地レビュー用。

## 起点と前提

- 開始HEAD: `d806571c4050f643662e002f20d4415b3a5913ff`（main、clean）
- Jinba上流: `e5f35e57e14d3998249a559c620a9286c95b4595`（開始時と同じ。リポジトリへは同梱せず、
  開発時に `/tmp/jinba` へcloneして比較）
- 対象は個人開発のBYOKアプリ。有料VPS・有料ベクトルDB・常時稼働クラウドは追加していない。
- GitHub Actionsは予算上限のため `.github/workflows/quality.yml` を
  `workflow_dispatch` のみに変更（push/PRでは動かない）。

## このセッションのコミット

| SHA | 内容 |
|---|---|
| `68140788` | モデル別コンテキスト・トークン予算・設定UI |
| `e37cfb50` | 根拠パック、決定・人物・前回最終版の横断 |
| `63d262e7` | 資料の型スケール、Jinba表ルール |
| `bb3df230` | GitHub Actionsを手動のみに |
| `2a7baa67` | 二段階検索・調査範囲・深い文脈検査 |
| `ca8a5535` | チャート凡例・表・コンテキスト圧縮 |
| `7315e188` | 根拠パックの資料保存と品質画面 |
| `ed3f589e` | Jinba比較レポート/比較スクリプト（Bitrigが記録） |
| `f0432d7b` | 前回最終版との差分、Jinba比較 |
| `fce09b05` | 決定語・人物発言を検索/根拠へ |
| `6b1ed5aa` | 実務3シナリオの生成・検査 |
| `e2ad0a9c` | m21/m02をJinba部品へ整合 |
| `447e7f05` | ページ番号、進捗表示、権限追従、m03 |
| `6c8ab183` | m04/b03、用途別予算表示、三角形、権限警告 |
| `7ef55b7c` | ページ番号の回帰検査 |

## 実装したもの

### 1. モデル別コンテキスト（P0-C）

- `App/ModelCapabilities.swift`
  - 完全一致のモデルIDだけカタログ参照。未登録・独自エンドポイントは保守値
    （32,768 tokens / 8,192 出力 / 512KiB）。
  - コンテキスト窓、最大出力、ツール/推論/構造化出力/画像、料金、キャッシュ、
    最大リクエストサイズ、取得元、最終確認日時。
  - 料金は未確認なら `nil`。`verifiedAt` が無いものは「未検証」と表示。
  - 利用者上書き `ModelCapabilityOverride`（UserDefaults、設定画面から）。
- `App/TokenBudgetManager.swift`
  - `chat / agent / deepAnalysis / presentation / research` ごとの目標。
    窓 − 出力予約 − 安全余白から入力を算出。固定40,000文字を廃止。
  - `DeepContextPolicy` が資料作成・経営報告・経緯・Deep Research等を判定。
  - 日本語は1文字≒1トークンの安全側。`TokenEstimate` に分離。
- `App/ModelBudgetScaling.swift`
  - `AgentSessionBudget` / `AgentRunBudget` をモデル上限へ拡張（有限のまま）。
- `CloudAgentSession` は `max_tokens` と出力予約をモデル上限内へ。
- 添付は解析60,000文字まで保持し、送信時にモデル別予算で制限。
- `AgentContextCompactor` が送信直前に古いツール結果だけを短縮（依頼文・直近・
  tool_call対応は保持）。OpenAI互換/Anthropic両対応。
- 設定 › AIと要約 › モデルの上限 に用途別の入力/出力予算と料金確認状態を表示。

### 2. 背景理解（P0-B）

- `App/PresentationEvidencePack.swift`
  - 目的・読者・判断事項、プロジェクト、時系列、決定、関係者、事実、数値、矛盾、
    リスク、未確認、前回最終版、前回差分、出典、権限、版、調査範囲、不足。
  - 参照不可は本文へ入れない。許可未確認もクラウド資料では使わない。
  - 二段階検索: 依頼語で採点 → 上位記録の頻出語へ展開。全資料の2割超に出る語と
    数字のみの語は除外。依頼語自体も頻出語を除外。
  - 決定は主題の時系列＋明示 `supersedes` で現在有効を解決。撤回・中止は現行にしない。
  - 矛盾は同一語を含み数値が異なる抜粋を警告（正否は断定しない）。
  - 前回最終版の数値と新資料を比べ、新出数値と未確認の旧数値を列挙。
  - 許可済み資料は1回2,000件まで、最終的な文字数も予算内。
- `App/MemoraModel+PresentationContext.swift`
  - 会議・要約・決定・未決・タスク・資料・人物・長期メモリ・ジャーナルを横断。
  - 前回最終版（artifact付きスライド）を優先。草稿は最終版と呼ばない。
  - 人物は名前・参加会議・本人の発言・明示的に割り当てられた未完了タスクのみ。
    人物メモは送らない。同姓同名はperson IDで区別。
- `MemoraModel+Agent` は深い依頼で検索結果より先に根拠パックを渡し、読取記録を登録。
  進捗に「候補N件 / 採用M件 / 現在の決定K件」を表示。
- 生成したスライドは `MemoraDocument.presentationEvidence` として保存（optional）。
  品質画面で目的・決定・前回差分・矛盾・不足・未確認・権限を確認できる。
- 参照権限が変わった記録がある場合は品質画面で警告し、その決定を現在として表示しない。
- PowerPointスキルの手順に、決定の現在性・最終提出版の再利用・矛盾/未確認・
  Jinba規約優先を追記。

### 3. 資料品質（P0-Aの一部）

- `App/PresentationTypography.swift`: 表紙/タイトル/見出し/本文/数値/注記/出典/
  ページ番号の型スケールと12カラムグリッド。
- タイトル30→24pt、表見出しを本文+3pt・太字・塗りなし、データ行のみ横罫線、
  最終行下罫線なし、表紙/章扉の出典行なし。
- チャート凡例をプロット右上へ移動。
- Jinba部品へ合わせたレイアウト: m02 調査根拠、m03 大型数値、m04 KPIタイル、
  m21 番号付き施策、b03 目次。因果2カラムの「→」文字を三角形へ。
- 表紙・章扉を除くページに右下ページ番号（画面/PDF/PPTX/会社テンプレート共通）。
- `PresentationValidator` にJinba由来の注意（常体タイトル、文型の偏り、
  分類ラベルの前置き、円グラフの区分過多、曖昧な列名、「—」連結）を追加。

### 4. 検証・成果物

- 追加検査:
  - `tools/checks/ModelCapabilitiesChecks.swift`
  - `tools/checks/AgentContextCompactorChecks.swift`
  - `tools/checks/PresentationContextChecks.swift`
  - `tools/checks/PresentationDeepContextChecks.swift`（129資料、複数年、同姓同名、
    撤回、権限取消、語の異なる重要記録、矛盾、前回差分）
  - `tools/checks/PresentationScenarioChecks.swift`（架空のA/B/C 3シナリオ）
  - `tools/checks/compare-jinba-catalog.swift`
- 実務シナリオ成果物: `docs/presentation-integration/scenarios/`
  - A 経営会議向け事業報告（8枚）、B 営業提案（8枚）、C 既存資料の更新（6枚）
  - 各PPTX/PDF/ページPNG。構造・版面エラー0、機械注意0。
- Jinba比較: `docs/presentation-integration/JINBA_COMPARISON_2026_10.md`
  - 65/65比較、機械的な差あり38/65。目視・Office実描画の合格0/65。
- 実行済み: `run-presentation-checks.sh`（65型＋3シナリオ）、
  `run-company-presentation-checks.sh`（65/65）、`run-backup-restore-checks.sh`、
  `run-cloud-session-checks.sh`、`run-slide-checks.sh`、Debugビルド、iOSプレビュー。

## レビューしてほしい箇所（優先）

1. **プライバシー**: `presentationEvidence` は生成時点の本文抜粋をSQLite/バックアップへ
   保存する。表示時は決定と警告を権限で絞るが、`keyFacts` の生テキストは残る。
   権限取消後の赤action・削除・再生成導線が必要か。バックアップ経由の持ち出しも含む。
2. **根拠パックの決定解決**: 主題キーは「会議名＋決定文の先頭48文字」で、
   異なる言い回しの交代は `supersedes` が無いと繋がらない。実データでの精度評価が必要。
3. **変更差分**: 数値抽出は正規表現で、年・ページ・型番も拾う。実資料での誤検知が多い可能性。
4. **人物の誤紐付け**: タスクは `assigneePersonID` のみ、発言は話者名一致。
   話者名が「話者1」の場合は取れない。役職・意見変化は未構造化。
5. **検索**: まだ字句（gram）ベース。意味検索/埋め込みは未導入。語展開の閾値
   （全体の2割、数字除外）はヒューリスティック。
6. **トークン予算**: 文字数からの推定で、提供元トークナイザー未使用。料金は未確認のため
   常に「未確認」。モデル窓・料金はアプリ宣言値で、提供元API未検証。
7. **圧縮**: 送信配列だけを短縮し、ローカルの `messages` は伸び続ける。
   長い実行でのメモリと、圧縮で落とした根拠の再取得保証を確認したい。
8. **ページ番号/フッター**: 構造化スライドのみ。旧アウトラインのページ分割スライドには
   付かない。Validatorは常にpageNumber=1で検査するため、実ページ番号の桁溢れは未検査。
9. **Jinba忠実度**: 残り38型は余白・情報密度・見本固有のフッター/大きな見出しが主因。
   機械比較は色・書体・美しさを判定しない。b03は変更後に機械指標が悪化しており、
   目視で妥当か確認が必要。
10. **資料の表現力**: 画像・リッチテキスト・グループ図形・ネイティブチャートは未対応。
    企業マスターの任意レイアウト追加・全ページ再配置も未実装。
11. **中断復旧**: 根拠パックは完成資料にのみ保存。生成途中の調査状態・ストーリーラインの
    復旧は未実装。
12. **実LLM検証**: シナリオは固定文。実モデルでの文章品質・論理・数値保持は未検証。
13. **CI**: GitHub Actionsは手動のみ。新しい検査はローカルでのみ実行されている。

## 再現コマンド

```bash
bash tools/checks/run-presentation-checks.sh          # 65型 + 3シナリオ
bash tools/checks/run-company-presentation-checks.sh  # 会社テンプレート65/65
bash tools/checks/run-backup-restore-checks.sh
bash tools/checks/run-cloud-session-checks.sh
bash tools/checks/run-slide-checks.sh
MEMORA_SCENARIO_OUTPUT=docs/presentation-integration/scenarios \
  bash tools/checks/run-presentation-scenario-checks.sh
# Jinba比較（Jinbaを別途clone）
swiftc App/SlideArchetype.swift tools/checks/compare-jinba-catalog.swift -o /tmp/jinba-compare
/tmp/jinba-compare /tmp/jinba/assets/SlideCatalog_16x9.pdf <presentation出力>/output \
  docs/presentation-integration/JINBA_COMPARISON_2026_10.md
```

## 未完了（環境依存）

- 実LLM API（BYOK）での生成・レビュー、モデル窓/料金の提供元確認
- PowerPoint/Keynoteでの実描画、実機VoiceOver、最終目視
- 残り38型の視覚調整の妥当性判断
