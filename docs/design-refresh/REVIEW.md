# デザインレビュー — 2026-10-19〜20

実装仕様・Design Tokens・共通コンポーネント一覧は [DESIGN.md](../../DESIGN.md)、
公式Webトークンとネイティブ設計値の区別は [調査記録](PLAN.md) を参照。
ChatGPT iOSの非公開値を測定済みとは扱っていない。

## Before / After

iPhone 18 Pro Maxのシミュレータで保存したPNG。下記は画面ごとのLight / Dark。
日付・レコードの表示は実データ、長文検証は明示的な架空データを使用した。

| 画面 | Before Light / Dark | After Light / Dark | レビュー観点 |
|---|---|---|---|
| Ask AI・空 | [L](before/ask-empty-light.png) / [D](before/ask-empty-dark.png) | [L](after/ask-empty-light.png) / [D](after/ask-empty-dark.png) | 空白を維持、入力とナビゲーションだけを強調 |
| Ask AI・会話 | [L](before/ask-conversation-light.png) / [D](before/ask-conversation-dark.png) | [L・表示検証](after/ask-conversation-fixture-light.png) / [D・表示検証](after/ask-conversation-fixture-dark.png) | 本人のメッセージのみバブル、回答はページ上の文章 |
| Ask AI・@候補 | [L](before/ask-mentions-light.png) / [D](before/ask-mentions-dark.png) | [L](after/ask-mentions-light.png) / [D](after/ask-mentions-dark.png) | 候補、利用状態、スクロール、入力フォーカス |
| 会議要約 | [L](before/summary-light.png) / [D](before/summary-dark.png) | [L](after/summary-light.png) / [D](after/summary-dark.png) | 同じ会議の本文・見出し・リスト |
| ジャーナル・今日 | [L](before/journal-light.png) / [D](before/journal-dark.png) | [L](after/journal-light.png) / [D](after/journal-dark.png) | フラットな週表示、タスク、余白 |
| ジャーナル・タイムライン | [L](before/journal-activity-light.png) / [D](before/journal-activity-dark.png) | [L](after/journal-activity-light.png) / [D](after/journal-activity-dark.png) | アイコン・接続線・記録の階層 |
| 日次サマリー | [L](before/journal-summary-light.png) / [D](before/journal-summary-dark.png) | [L](after/journal-summary-light.png) / [D](after/journal-summary-dark.png) | 強制Darkを撤去、写真を小さなヘッダーに限定 |
| ライブラリ | [L](before/library-light.png) / [D](before/library-dark.png) | [L](after/library-light.png) / [D](after/library-dark.png) | タイトル・種類・日時・プレビューの順序 |
| ワークスペース | [L](before/workspace-light.png) / [D](before/workspace-dark.png) | [L](after/workspace-light.png) / [D](after/workspace-dark.png) | チャット／ファイル／ソースを維持、フラットなタブ |
| 設定 | [L](before/settings-light.png) / [D](before/settings-dark.png) | [L](after/settings-light.png) / [D](after/settings-dark.png) | 中立色のSF Symbols、システムForm |

## 追加の確認画像

- 長文・見出し・箇条書き・引用・表を持つ実際の要約エディタ：
  [Light](after/summary-fixture-light.png) / [Dark](after/summary-fixture-dark.png)。
  DEBUGの「デザインと保存の検証」で明示的に作成し、E2Eでは編集・再起動・SQLite再読込後に削除。
- プロジェクト内で実際に追加したメモの@指定：[画像](after/workspace-mention-light.png)。
  このソースはプロジェクト専用であり、全体のAsk AIへ持ち越した場合は利用不可と表示する。
- 最大アクセシビリティ文字サイズの候補：[画像](after/ask-mentions-accessibility.png)。
  候補リストを縦積みにし、ヘッダーも含めた全体の高さを制限。アイコンは文字と同じ倍率で巨大化させない。
  横幅に収まらない見出しは「候補」に短縮し、読み上げ名は維持する。
- 同じ最大文字サイズでの検索：[画像](after/search-accessibility.png)。
  検索語の消去後もキーボードを維持し、キャンセルは別行に配置する。

## 撮影条件と限界

- 通常の比較画像はDynamic Typeの標準Large。変更前の会話／@入力画像は
  初期状態の拡大文字を含むため、同一文字サイズのピクセル比較ではない。
- 撮影経路によってPNG解像度・ステータスバー時刻は異なる。等寸のピクセル回帰テストではない。
- 変更前の@入力は候補が表示されていない状態を記録した。変更後は実際の候補を撮影。
- 変更前の会話は既存会話、変更後の会話画像は既存のDEBUG表示検証画面。
  同じ会話内容の比較ではなく、実際のAIResponseTextの文字組み確認。モデル呼び出しは行っていない。
- 長文要約の架空データは表示／保存経路の検証であり、AI生成品質の検証ではない。
- Lightへの切替直後にキーボードだけ前の外観が残る画像がある。アプリの描画色とは別のシステム状態。
- VoiceOverは候補・閉じる・入力・追加・削除のラベルをアクセシビリティツリーで確認。
  画面全体の読み上げ順序の聴取テストや実機支援技術テストまで完了したとはしない。
- 比較画像は代表画面。全設定・連携サービス・全エラー状態の画像網羅ではない。

## 移行の整理

- 色・文字・余白・角丸・モーションは単一の共通実装。旧MONOCHROME_DESIGNは現行仕様への参照に変更。
- 旧Glassのコンテンツ用セグメント、任意のカード角丸、Lucide依存、設定の色付きタイル分岐を削除。
- 本文・リスト・カレンダーはフラット。Glassは既存のナビゲーション／入力／作成操作に限定。
- レイアウトの数値指定は共通UIを中心に移行。画像編集の幾何、PDF／スライドの紙面座標、
  波形、既存アニメーションの計算、ヘアライン、DEBUG比較用ベースラインは一律変換しない。
  これらを第二のデザインシステムとして使わない。
- SQLiteのレコード形式、Markdown保存形式、メディアファイル参照、既存のナビゲーション識別子は維持。
