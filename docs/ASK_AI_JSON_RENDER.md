# Ask AI: 公式json-renderランタイム

前回のSwiftUI限定アダプターに加え、**公開版json-render 0.23.1の公式ランタイム**を
アプリへ同梱する。対応済みとする範囲は、Ask AIの生成UIに使うcore / React /
shadcn / directives / YAML。別の表示先用のVue・Svelte・React Native・Next.js・
動画・PDF・3D・メール等の各アダプターを重ねてアプリへ組み込むものではない。
それらまで含むリポジトリ全体の実装と、この生成UI統合を混同しない。

上流: https://github.com/vercel-labs/json-render
固定バージョン・推移依存・整合性ハッシュ: `tools/json-render/package-lock.json`。

## 構成

- `@json-render/core`, `@json-render/react`, `@json-render/shadcn`,
  `@json-render/directives`, `@json-render/yaml`: **0.23.1**。
- React / React DOM: **19.2.4**。上流のRenderer / JSONUIProvider / defineRegistry /
  StateStore / SpecStreamCompiler / YAML compilerを直接使う。機能のSwift模倣ではない。
- 公式shadcn **全36部品**を登録。追加のMetric / BarChart / Panelを含め39部品。
  ビルド時に同じカタログからモデル用プロンプトとJSON Schemaを生成する。
- 周囲のチャット・ナビゲーション・承認カードは既存のSwiftUI。
  生成UIの部分をWKWebViewで表示。通信不要のHTML/CSS/JSを1つにバンドルする。
- 従来の`memora-ui`と限定`json-render`回答は既存のネイティブ表示を維持。

## 対応機能

| 機能 | 実装 |
| --- | --- |
| コンポーネントカタログ・レジストリ | 公式全36部品 + Memora用3部品 |
| レイアウト・フォーム・表示・タブ・ダイアログ・ドロワー等 | 公式shadcnコンポーネントをそのまま使用 |
| 状態・双方向バインディング | StateStore, `$state`, `$bindState`, `$bindItem` |
| 条件表示・条件付きプロパティ | visible, AND/OR/比較, `$cond/$then/$else` |
| 繰り返し | repeat, `$item`, `$index`, 入れ子のitem path |
| スロット | childrenに加え名前付きslots。Panelがheader/footerを宣言 |
| 式 | `$template`, `$computed`。sum/average/count/min/maxを登録 |
| 標準ディレクティブ | format/math/concat/count/truncate/pluralize/join/t |
| イベント・状態監視 | on, watch, 複数アクション、動的パラメーター |
| アクション | setState/pushState/removeState/validateForm/push/pop、確認、onSuccess/onError |
| アプリへの操作 | copyText/openURL/askAI/completeTaskを明示的に登録 |
| フォーム検証 | 公式checks、change/blur/submit、エラー表示 |
| 入力形式 | flat JSON、nested JSON、JSONL SpecStream、YAML |
| 更新形式 | RFC6902 add/remove/replace/move/copy/test、JSON Merge Patch、YAML edit/patch、unified diff |
| 途中表示 | 公式SpecStreamCompilerを同じ受信中に保持。追記だけを走査し、以前のpatchを再適用しない |
| 保存・復元 | SQLiteの会話resumeと質問履歴に検証済みspec・ローカル状態・表示文を保存 |
| コピー・共有・資料保存 | Markdownと生成UIの表示文・非パスワード入力値を展開 |
| アクセシビリティ | 公式ARIA/ラベル、Dynamic Type、明暗、Reduce Motion、フォーム操作 |

## モデル経路

グローバルのクラウドエージェント、クラウドの通常回答、プロジェクト/記録の
読み取り専用セッションへ公式カタログの生成プロンプトを渡す。
オンデバイスにはコンパクトな同形式の指示を渡す。
通常の質問にはMarkdownだけで答え、UIが有用な依頼だけ構造化表示を付ける。
モデルが生成しない場合も自動で別モデルを呼ばない。

クラウドは上流の標準`spec`フェンス内JSONLが基本。従来の`json-render`フルJSON、
`yaml-spec` / `yaml-edit` / `yaml-patch` / `diff`、フェンスなし混在JSONLも受け付ける。
JSON内を引用リンク変換に通さず、分離したMarkdownだけへリンクを付ける。
新しい回答での差分更新は、同じ会話の直前の検証済みspecを初期値にする。
復元時は保存した完成specを描画し、古いpatchや操作を再実行しない。

UIの入力状態はモデルへの履歴・個人メモリへ追加しない。`askAI`を押しても質問は
編集可能な下書きへ用意するだけで、自動送信せず、既存の下書き/添付/メンションを守る。

## アプリ境界

- モデルが渡すのは宣言的なUIデータ。HTMLやJavaScriptとして実行しない。
  WKWebViewへは構造化された引数で渡す。
- 固定のbundled scriptにSHA-256付きCSP。connect/frame/object/base/form送信を禁止。
  Image/Avatarはdata/blobかplaceholder。任意の外部画像URLを自動取得しない。
- ネイティブのメッセージはメインフレーム・bundle URL・セッショントークン・回答の
  SHA-256を照合する。会話/ワークスペース/世代の変更、保護、復元、途中生成を再確認。
- 外部操作は人のボタン操作からだけ。HTTPSリンクはネイティブの確認後に開く。
  clipboardは明示操作、質問は下書き、タスクは元回答の実在UUIDと一時権限を再検証し、
  既存のツールregistry/policy/承認カードを通す。JSONから任意のツールを呼べない。
- UI状態の保存は権限の保存ではない。会話復元・履歴の継続でwrite grantを戻さない。
- パスワード入力を含むUIの入力状態は永続化しない。パスワード値はコピー用本文へ含めない。
- UIデータ256KiB、状態64KiB、256要素、配列200件、表示深度16段。
  未知部品/操作、循環、共有ノード、不正path、prototype汚染、状態更新ループを拒否する。
  上流が任意に拡張可能であることは、アプリの任意コード/権限実行を認める意味ではない。
- 公式ランタイムのライセンスと、実際にbundleへ入る推移依存90パッケージの告知を同梱し、
  設定のオープンソースライセンスから読める。

## ビルド・検証

```sh
npm ci --prefix tools/json-render --ignore-scripts
npm --prefix tools/json-render run build
bash tools/checks/run-json-render-checks.sh
bitrig preview -platform iOS
```

`App/Resources/JSONRenderRuntime.html`等は再現可能な生成物として同梱するため、
通常のiOSビルドやアプリ利用にNode・npm・CDN・外部サーバーは不要。

- `runtime.test.mjs`: 公式コンパイラー/式/全更新形式、状態境界、CSP/告知、
  追記だけの処理と再適用の拒否。
- `runtime.dom.test.mjs`: 全39部品の公式registry描画、実DOMでの入力/検証/
  タブ/visible/repeat/bindItem/slots/Dialog/watch/確認/パラメーター/onSuccess。
- `JSONRenderEnvelopeChecks`: wire分離、未完了入力、通常コードを誤解釈しないこと、
  サイズ、SHA-256、実SQLiteの書込/再読込。
- `JSONRenderContextChecks`: 本番の状態保存/下書き保護、古いcontext/本文/会話/
  ワークスペース等9境界、履歴保存と古いfingerprintの拒否。モデルのrecord形状はfixture。
- `AIConversationSnapshotChecks`: 本番codecで会話と履歴の生成UI状態を復元。
  古いUI状態は復元せず、履歴の壊れたUIも回答本文を妨げない。write grantは復元しない。

設定 > 診断とプレビュー > 状態と復旧UIを確認 > **生成UI（フォームと操作）**。
固定の架空データでフォーム / JSON Patch / YAMLとストリーミングを確認できる。

実クラウドモデルの生成品質、実記録の値の正確さ、実端末/外部サービスの往復は、
コンパイルや固定fixtureの成功とは別の検証である。

### 今回の確認結果

- iOSの`bitrig preview`ビルド成功。既存の警告は残る。
- 追加のSwift境界検査とJavaScript/DOMの12テストが成功。
- 会話codec、既存のクラウドセッション、引用、タスク承認/保存、カレンダー権限とbranch integration検査も成功。
- iPhoneシミュレーターで、名前入力→テンプレート文の即時反映、タブと条件付きスロットの切替、コピーのネイティブ往復、Dialogの開閉と入力保持を実操作で確認。
- 実クラウドモデルの生成往復は未検証。固定データの表示・操作確認をその証拠として扱わない。
