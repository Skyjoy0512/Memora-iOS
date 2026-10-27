# Memora統合開発・実行記録

開始: 2026-10-27。GitHub main取得済み。開始HEAD:
`5389cf7e061d8ef76d1e3c3aacd5b3d1c87e0db7`。開始時の作業ツリーはclean。

## 監査と完成基準

| 領域 | 開始時点の分類 | 根拠・不足 |
|---|---|---|
| 標準PowerPoint | 実装済み・既存ホスト検証あり | DocumentSlideはtitle/bullets/notes。SlidePageLayoutを画面/PDF/PPTXで共有。65型なし |
| 会社テンプレート | 限定実装 | CompanyTemplateEngine v2。既存パーツを保持するマーカー置換。自動マスター選択・任意レイアウト追加は未実装 |
| 高度なグラフ | PoCのみ | docs/comprehensive-improvement/quicklook-findings.json。折れ線・円がQuick Lookで欠落。Office実描画未検証 |
| 資料編集 | 限定実装 | アウトライン編集・revision/原本保持。数値/表/レイアウトの個別編集なし |
| AskAI/Skills/プラグイン | 実装済み・実API未検証 | BYOK、端末内、承認、出典、workspace境界。PowerPointツールは箇条書きのみ |
| ResidentAgent | 実装済み・OS実行時刻は非保証 | 読み取り限定BYOK、BGTask、回数/時間制約。クラウド常駐なし |
| 録音/文字起こし | 実装済み・実機耐久未検証 | 復旧/省電力コードとホスト検査あり。強制終了AAC問題は解決済みと扱わない |
| Journal/Library/Project | 実装済み・一部画面検証記録あり | サイドメニュー、上部create、チャット/ファイル/ソース順を維持 |
| Web source | 実装済み | 正規化、DNS pinning、redirect/size/timeout検証。貼り付けからの共通インライン導線は未実装 |
| デザイン | 実装済み | DESIGN.mdとMemoraPalette/Spacing/Typography。短いshimmerは既に実装済み |
| 認証/購入/クラウド | 未接続 | ローカル設定を実ログイン/購入済み/同期と表示しない |
| SQLite/backup | 実装済み・ホスト検証あり | LocalStore/RecordStore、エクスポート版管理。資料配列全体のエンコードは残存 |
| Widget/Live Activity | 実装済み・実機未検証 | Sharedのsnapshot/recording attributes。今回の資料モデルを共有targetへ混入させない |
| CI | 6スイート定義済み | quality.yml。ローカル実行とGitHub Actions実行を区別 |
| OSS告知 | リソース同梱済み・集約画面不足 | THIRD_PARTY.mdとApp/Resources。依存本体/モデル/参考のみを区別 |

コード存在のみで完成とはしない。65型の最終完成にはネイティブ、PDF、PPTXの実描画、
編集、互換性、不正入力、出典と数値の保持が必要。未実行を成功と記録しない。

## 上流仕様の固定

- https://github.com/carnot-tech/jinba-consulting-pptx-skill
- 取得HEAD: `e5f35e57e14d3998249a559c620a9286c95b4595` (2026-10-26)
- MIT: Copyright (c) 2026 Carnot AI Inc.。TRADEMARK.mdはコード許諾と別。
- `references/archetype-catalog.md`: b01–b30、m01–m35。IDとsemantic IDを対応させる。
- 最新SKILLの既定は検査済み20型を優先するが、今回の要求により65型を対象とする。
- Golden reference: 2つのHTMLパーツ集、65ページPDF。SuperTemplateは62型でb28–30なし。
- `new_deck.py`/`rules.py`: 構成→関係→型。`check_deck.py`/`check_layout.mjs`/
  `check_all.py`: 内容と版面の検査を分ける。`content-review-prompt.md`と
  `ai-smell-lexicon.md`: 根拠のない断定・重複・不自然な日本語を見直す。
- `html_to_pptx.py`: SVG図表がラスター化されるためiOSランタイムに採用しない。
- `measure_deck.py`/`deck_pptx.py`: 企業マスター優先、theme/placeholderの計測と再利用。
- `snapshot.py`: 実レンダリングで確認する思想を採用。Chromium/Node/PythonをiPhoneに同梱しない。
- 広告文、他社商標/ロゴを資料生成に注入しない。成果物へのクレジットは上流でも任意。

## 設計

既存DocumentSlideにoptionalの構造化内容を追加し、nilなら従来のページ分割を使う。
構造化ページは共通のベクター要素列を生成し、画面/PDF/OOXMLに同じ座標を渡す。
データ欠落をサンプルや別の箇条書きに置換しない。必要項目/容量/文字あふれを診断する。
資料テーマはアプリUIトークンから独立し、白/黒/青/オレンジ。会社原本は保持する。
モデル呼出を追加せず、既存のcreate_slides承認・保存・BYOK経路を拡張する。
スライド単位編集は楽観的競合検出と保存成功後のmodel更新を使う。

## 実行ログ

- Phase A: 最新mainと上流の取得、既存実装/制約/検証境界を記録。
- 開始時の6スイートとDebug previewを実行中。結果は後続コミットで記録する。
