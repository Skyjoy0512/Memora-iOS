# Ask AI 回答表示の修復

2026-11-19。ユーザーの「デザイン崩れてる」「Ask AIの回答表示」を優先した修復単位。
全体安定化の完了報告ではない。全体の残作業は [REVIEW.md](REVIEW.md) を参照。

## 調査・根本原因

別会話による公式json-render統合が進行していたため、その未コミット変更は保持した。
同統合のコミット `bba067ea` を基準として、以下を修正した。
通常の日本語Markdown本文・表・コードブロックも既存fixtureで確認した。

| 問題 | 原因 | 修正 |
|---|---|---|
| 生成UIの枠が途中で切れ、本文と別々に動く | 700ptの上限とWKWebView内の縦スクロール | 内容の高さでフレームを決め、周囲の会話がスクロールを管理 |
| 補足を閉じても空白が残り得る | `scrollHeight` が現在のviewport高より小さくならない | bodyの実際の矩形を計測して縮小も反映 |
| 長文末尾の操作で背景だけ暗くなりDialogが見えない | 固定表示の中央が長いWeb文書全体を基準にする | ネイティブwindow・クリップする祖先と交差した可視範囲を通知し、その中へ表示 |
| 確認UIの明暗が周囲と不一致 | 上流の確認UIが固定の白背景をinlineで設定 | 既存のテーマ色へ合わせ、危険操作の赤は保持 |

長文Dialogの不具合は固定データで再現した。修正前実行
`01a1ea31-8386-71c3-9f89-d27a3f4e340d` はDialogの可視性で失敗し、
背景だけ暗い状態を撮影した。正常な実行として数えていない。

## 修正前後の構造

- 以前: 会話ScrollView → 高さ上限700ptのWKWebView → 内側のスクロール。
- 変更後: 会話ScrollView → 実寸で伸縮するWKWebView。表など各部品本来の操作は保持。
- Dialog / Drawer / 操作確認: bundle内のランタイムが表示を検知し、認証済みbridgeで
  可視範囲を要求。ネイティブが幾何情報だけを返し、表示位置と最大高へ反映する。
- タイマー・ポーリング・モデル呼び出し・別のレンダラーは追加していない。
  上流の36部品とアプリ用3部品、状態管理・イベント・承認境界は引き続き既存実装を使う。

## 比較画像

すべて実際のiOSシミュレーターのキャプチャ。架空の固定データであり、実モデルの回答ではない。
キャプチャ画像の生成・合成・加工は行っていない。

| 状態 | 修正前 | 修正後 |
|---|---|---|
| 生成UI末尾 | [枠の途中で切れる](screenshots/answer-before.png) | [会話と一緒にスクロール](screenshots/answer-after.png) |
| 長文末尾からDialogを開く | [背景だけ暗くなる](screenshots/answer-long-dialog-before.png) | [可視範囲に表示](screenshots/answer-long-dialog-after.png) |

[ダークモードの確認UI](screenshots/answer-confirmation-dark.png) /
[補足を閉じた後](screenshots/answer-collapsed.png)。

## 変更ファイル

- `App/JSONRenderAnswerView.swift`: フレームの上限を外す。
- `App/JSONRenderWebView.swift`: 内側の縦スクロール停止、可視範囲の通知。
- `tools/json-render/runtime.jsx`: 実寸計測、Dialog等の検知と幾何情報の適用。
- `tools/json-render/styles.css`: 可視範囲内の配置と確認UIの明暗。
- `App/Resources/JSONRenderRuntime.html`: 固定した依存関係から再生成したbundle。
- `tools/json-render/build.mjs`, `App/Resources/JSONRenderLongExample.txt`,
  `App/JSONRenderExampleView.swift`: 長文の固定fixture。DEBUGの既存診断画面でのみ選択。
- `tests/answer-layout.e2e.ts`: 通常・長文の表示、スクロール、末尾操作、明暗、Dialog、
  確認のキャンセル、折り畳み後の余白を検査。
- `tests/memora.e2e.ts`: 既存の構造化回答検査を、実際のボタンが静止してから開くように修正。
- `DESIGN.md`, `docs/ASK_AI_JSON_RENDER.md`: 伸縮・スクロールの契約とfixtureを記録。
- 本資料、`REVIEW.md`、比較画像6枚。

## ビルド・検証

対象: iPhone 18 Pro Max / iOS Simulator、iOS 26 deployment target、iOS 27.2 SDK。
利用者のプレビューは初期化せず、E2Eは既存helperが管理する専用テスト端末で実行した。

| 検証 | 成功 | 失敗 | 未実行・範囲外 |
|---|---:|---:|---|
| `bitrig preview -platform iOS` | 1 | 0 | 実機は対象外 |
| JSONRenderEnvelopeChecks / JSONRenderContextChecks | 2グループ | 0 | 実モデル評価ではない |
| 既存JS/DOMテスト | 12件 | 0 | ネイティブ実機の証明ではない |
| 最終UI E2E | 5件 | 0 | 発見140件のうち135件は今回の選択対象外 |

最終UI実行: `01a1f0ee-686e-71c1-a1ef-4c938af2068f`。
発見140、選択5、実行5、成功5、失敗0、中断0、選択後スキップ0。
runnerには選択対象外の135件も非実行として残る。全140件の合格とは扱わない。
modelTokens=0、maxModelCallsInStep=0、downloads=0。

選択したUI検査:

1. 通常フォーム: 本文との相対位置を維持したスクロール、末尾までの表示、明暗、Dialog開閉、補足の縮小。
2. 長文: 同じ検査に加え、末尾からの確認UIをDarkで表示しキャンセル。
3. 日本語本文の文字組み: 表・引用・コードを含むLight / Dark。
4. 既存ネイティブの比較表とRow。
5. 既存ネイティブのストリーミング再生。

UI検証中のApp / Shared / ランタイム / テスト1648ファイルに変更なし。
内容リビジョン一覧のSHA-256:
`dd9115c908d26e5fef96ab7756e55e6b1d5649a5283ad40d30512690c5793a63`。
最終プレビューのbundle内HTMLとfixtureも作業ツリーの生成物に一致した。

最終ビルドログ: `2026-11-19T08-16-14-5f23fea8.log`。
既存のMapKit / OAuth / App Intents関連警告11件が残る。コンパイル・リンクエラーなし。
原本のE2Eレポートとhostログはgit管理外の `.e2e/answer-layout-verified-20261119/` と
`.e2e/answer-layout-host-20261119.log` に保存される。

再実行:

```sh
npm --prefix tools/json-render run build
bash tools/checks/run-json-render-checks.sh
bitrig preview -platform iOS
npx --no-install e2e run tests/answer-layout.e2e.ts tests/memora.e2e.ts tests/design-refresh.e2e.ts \
  --grep 'answer layout:|structured answer example|conversation typography' \
  --workers 1 --retries 0 --no-cache --trace on
```

## 中間実行の失敗

最終結果とは分けて保持した。Galleryの行が画面外、スクロール中のtap、
インストールの10秒タイムアウト、WebKitでDOMのDialogが`other`として公開されること、
Segmented Pickerが`tab`として公開されることによる検査側の失敗があった。
実際のAXツリーに沿って既存helperとlocatorを修正し、本番の制約や期待する表示を緩和していない。
実際の長文Dialogの失敗は上記の修正前画像・実行IDに対応する。

## 互換性・影響・セキュリティ

- 記録・会話・UI状態の保存形式、SQLiteのschema、バックアップを変更しない。移行不要。
  元の文章・要約・BYOK選択・プロンプトを変更しない。
- 新しいbridgeメッセージは表示用の幾何情報だけ。
  main frame / bundle URL / token / fingerprintの検査を通る。
  データ参照・タスク変更・外部操作の権限は追加しない。
- 外部送信先、ネットワーク許可、CSPの制約、依存バージョンを変更しない。
  再生成したscriptのCSP hashは既存host検査で確認した。
- 上流の操作確認に対するstyle補正は固定した0.23.1の実装形状に依存する。
  依存更新時にはDialog / Drawer / 確認UIと危険操作の配色を再確認する。
- 通常録音、文字起こし、音声入力、読み上げ、Live Activityに変更なし。
  Live音声対話の無効化flagや実行ガードも変更していない。

## 未測定・残作業

性能・メモリ・電池・発熱の比較測定はしていない。改善数値は報告しない。
描画面積は内容に応じて増えるため、極端に大きなUIのWebKitメモリは別途プロファイリングが必要。
ストレージには再生成bundle・固定の長文fixture・記録用画像を追加した。
実利用時のキャッシュ使用量は未測定。新規ライブラリ・課金・クラウド基盤はない。
生成品質は固定fixtureの表示確認のみ。実モデルの事実性、速度、要約品質の証明ではない。

小型iPhone / iPad / 最大Dynamic Type、VoiceOverの実聴、IME・キーボード表示中の
複雑なフォーム、回転中のmodal位置、実機の長時間利用は未検証。
録音から要約までの性能、共通知識、他画面の全体レビューなどは本単位の完了に含めない。

## Git

- 基準: `bba067ea` — Integrate official json-render runtime with interactive Ask AI answers。
- 修復: `5028b0ca` — Fix generated answer scrolling and visible dialog layout。
- 作業前fetch時点でBitrigのorigin/mainと一致。GitHub mainからの未取り込みコミットは0。
