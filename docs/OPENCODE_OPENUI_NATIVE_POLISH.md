# Intelligent UI ネイティブ仕上げ（OpenUI 由来）

2026-10-17。別担当がチャット本文・コンポーザーを担当する間に、構造化UI
（ComparisonTable / SourceList / TaskProgress）の表示品質だけを担当した。
調査で止めず、実装・ホスト検証・コミットまで行う。push / merge / cherry-pick はしない。

## 作業場所

- 参照元（共有ツリー、編集しない）:
  `/Users/ken/Library/Bitrig/Users/23515/Projects/a8e58691-1b31-4bb3-8c2f-f9dec163a2ea`
- 実作業 worktree（実体は開発用SSD）:
  `/Volumes/WorkspaceSSD/Development/Temp/memora-openui-native-polish-20261017`
- ブランチ: `feat/openui-native-polish`
- ベースSHA: `d028a070bc829ac0aaf6acc2d04a29b635888b8c`（main と同一）
- 元 main / 共有ツリー / `memora` worktree は変更していない。

## 変更ファイル

新規（表示部品・検証）:

- `App/AIInterfaceTableLayout.swift` — 比較表の列幅（純粋関数）
- `App/AIInterfaceComparisonTable.swift` — 比較表ビュー
- `App/AIInterfaceSourceList.swift` — 根拠一覧ビュー
- `App/AIInterfaceSourceListModel.swift` — 根拠行の解決（純粋関数）
- `App/AIInterfaceSourceRow.swift` — 根拠行の値型
- `App/AIInterfaceTaskProgressSummary.swift` — 進捗集計（純粋関数）
- `tools/checks/OpenUINativePolishChecks.swift`
- `tools/checks/run-openui-native-polish-checks.sh`

変更:

- `App/AIInterfaceTaskProgress.swift` — 実データ集計と内訳の折りたたみ
- `App/NativeAIInterfaceView.swift` — 比較表・根拠一覧を新部品へ委譲、比較表の根拠解決を追加、遷移先を internal 化
- `App/NativeAIInterface.swift` — ComparisonTable 行に任意の `referenceID` を許可（根拠導線）、指示文を1行追記

## 改善した画面・操作

### ComparisonTable

- 列見出しを secondary 色・semibold・`.isHeader` で本文と階層化。見出し下に罫線。
- 行ごとに hairline 区切り。本文は行間 3pt、上下 12pt の余白、上揃え。
- 列幅は内容量から算出し、見出しと本文で同一幅を共有。長文は列内で折り返す。
- 大きい文字サイズでは `@ScaledMetric` の最小列幅が効き、縮まず横スクロールする。
- 横スクロール・テキスト選択を維持。VoiceOver は「比較表。横にスクロールできます」。
- 根拠がある行だけ `referenceID` を付けられ、現在も許可された記録にだけ
  「根拠を開く」リンクが出る。無い／失効した ID はリンクなしで本文だけ表示。

### SourceList

- 記録の実タイトルを主、任意の補足（モデルの注記）を副、その下に接地メタデータ
  「会議 · 引用N件」を小さく表示。長い名前は折り返し（最大3行）。
- 実在し現在許可された記録だけがリンク。削除・失効した行は黙って消さず件数で報告。
- すべて無効なら空状態メッセージを1つ表示。VoiceOver は行を1要素にまとめ、
  資料アイコンとシェブロンは読み上げから外す。

### TaskProgress

- 件数・進捗率は許可済みの現在タスクから算出（表示JSONに数値を持たせない）。
- 「N件中M件が完了」「残りK件」「完了」を表示。バーは実値のみ。
- 2件以上のときだけ「内訳」を展開でき、各タスクを完了／未完了の記号で示す。
- Reduce Motion ではバーのアニメーションを止める。

通常の質問は従来どおり Markdown のまま。新しいカード・フォーム・装飾は増やしていない。

## OSS の参照箇所と対応

対象: OpenUI `8d9c4c3b108a7b5352192a6a9d7327bdf7ea19b5`（2026-10-16）。

| 元OSSの部品・操作 | 観察した点 | Memora の実装 |
| --- | --- | --- |
| `packages/react-ui/src/components/Table/Table.tsx`（`ScrollableTable`） | 列幅を内容から決め、見出しと本文で共有。はみ出す時だけ左右ボタンと横スクロール | `AIInterfaceTableLayout.swift` ＋ `AIInterfaceComparisonTable.swift` |
| `packages/react-ui/src/components/Table/table.scss` | 見出しは secondary のラベル、下罫線。行ごとに罫線、最終行は罫線なし。セルは上下パディング | 同上（罫線・余白・階層） |
| `packages/react-ui/src/components/Citation/Citation.tsx` / `citation.scss` | 本文に付く小さなリンク操作で根拠を開く | 比較表の行 `referenceID` リンク（遷移は既存 `AIInterfaceReferenceDestination`） |
| `packages/react-ui/src/components/Sources/Sources.tsx` / `SourcesItem.tsx` / `sources.scss` | 記録名を主、出典名を副、長い名前は省略、空なら何も出さない | `AIInterfaceSourceList.swift` ＋ `AIInterfaceSourceListModel.swift` |
| `packages/react-ui/src/components/MetricIndicator/MetricIndicator.tsx` | 見出し数値＋補足。値を捏造せず渡された値だけを整形 | `AIInterfaceTaskProgressSummary.swift` ＋ `AIInterfaceTaskProgress.swift` |

参照のみ（コード・素材・プロンプトは転載していない）:
`open-intelligent-ui` `6a4a0ba192ea285b3a5ed39dcc1295d7d4080d6f`（2026-10-15）。

## コード移植／独自実装の区別

- すべて独自の SwiftUI 実装。React/TSX のコードは1行もコピーしていない。
- 比較表の列幅は OpenUI の考え方を観察し、`AIInterfaceTableLayout` として独自に実装。
  チャット本文側の `AIResponseTableLayout` には依存しない（レーン分離のため）。
- ロゴ・favicon・画像・ブランド素材は持ち込んでいない（favicon 取得は行わない）。

## ライセンスと著作権表示

- OpenUI 本体は MIT。`LICENSE`（`8d9c4c3b…`）: `Copyright (c) 2011-2024 Thesys Inc.`
  本作業はコード転載なし（設計の参照のみ）のため、追加の notice 同梱は不要。
- `open-intelligent-ui` はリポジトリ内に LICENSE / package license field が無く、
  demo 全体の転載許諾は確認できない。コード・画像・プロンプトをコピーしていない。
- 既存の `App/Resources/ChatGPTUI-LICENSE.txt`（chatgpt-ios-ui, MIT,
  `dc6e6a52…`, `Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors`）は
  チャット本文側の担当が同梱したもので、本作業では変更していない。

## 実行したテストと結果

- `bash tools/checks/run-openui-native-polish-checks.sh` → 成功。
  比較表の列幅（短文で全幅・長文で配分・拡大文字でスクロール・0/負/NaN/∞ の幅・
  巨大セルの上限・空見出し・多列）、TaskProgress 集計（空・一部・全部）、
  根拠行の解決（実在／失効／欠落／空タイトル）、スキーマ（比較表の `referenceID` 許可、
  列数不一致・action・value・不正 UUID の拒否、TaskProgress の重複 ID 拒否）、
  完成部品単位のストリーミング。
- `bash tools/checks/run-openui-native-polish-checks.sh` の第2段 → 成功。
  新規 SwiftUI ビュー（比較表・根拠一覧・進捗）を実 iOS 27.1 SDK に対して
  `swiftc -typecheck`。アイコン補助と遷移先だけ最小スタブ。**ビューが型検査を通ることの
  確認であり、アプリのフルビルドや描画の確認ではない**（統合担当のビルドが最終判断）。
- `bash tools/checks/run-intelligent-ui-checks.sh` → 成功（既存の回帰なし）。
- `swiftc -parse`（新規・変更の Swift ファイル） → 構文成功。

## スクリーンショット

未取得。理由は「未実装・未検証事項」の Bitrig 制約を参照。
`docs/qa/opencode-openui/` に取得手順を残す。

## 未実装・未検証事項

- **Bitrig でビルドできない**: `bitrig build -list` は worktree を
  「Bitrig プロジェクトではない」と判定する。Bitrig は共有ツリーの Project.json を
  基準にプロジェクトを解決するため、この SSD worktree では Debug/Release ビルドと
  プレビューができない。統合担当に Debug / Release ビルドを依頼する。
  共有ツリーで動作中のプレビューは上書きしていない。
  代わりに `run-openui-native-polish-checks.sh` が新規ビューを実 SDK で型検査するが、
  これはスタブ併用のスモークテストであり、アプリ全体のリンクや実行時挙動は未確認。
- `NativeAIInterfaceView.swift`（変更）は MemoraModel など多数に依存するため単体の
  型検査は行っておらず、`swiftc -parse` のみ。統合後のビルドで確認する。
- 実機・シミュレータでの画面確認（Light / Dark / 大きい文字 / Reduce Motion）は未実施。
- VoiceOver の読み上げ、日本語 IME、実プロバイダーのストリーミング E2E は未検証。
- 比較表の行 `referenceID` は、モデルが実在 UUID を付けた場合のみリンクになる。
  実サービスでの生成品質（正しい UUID を付けるか）は未検証。
- SourceList の補足行（`item.detail`）はモデル記述であり、記録本文からの引用ではない。

## 統合担当が接続・確認すべき箇所

- `tools/checks/run-next-generation-checks.sh` に
  `bash tools/checks/run-openui-native-polish-checks.sh` を追加する。
- 統合後のツリーで `bitrig preview -platform iOS` と Debug / Release ビルドを実行し、
  比較表・根拠一覧・進捗の画面を Light / Dark / 大きい文字 / Reduce Motion で確認する。
- `AIInterfaceReferenceDestination` を `private` から internal へ変更した
  （新部品から遷移先を参照するため）。チャット本文側の同名参照と衝突しないこと。
- `NativeAIInterface.instructions` に ComparisonTable 行の任意 `referenceID` を追記した。
  既存の承認・権限・失効・実行予算は変更していない。
