# UI/UX確認

## 2026-10-26: 生成modeとDynamic Type

native-app-design/HIGに従い、既存の詳しさsegmented controlを保持し、その下に生成modeのnative menuを1つ追加。通常の画面構成・モノトーン・ロゴ・Glassの適用箇所は変えない。未知モデルで設定を適用しないことと、並列中断の料金注意を表示する。選択のみではAI処理を開始しない。

実Simulatorの確認で、エンジン名の折返しが説明文と重なる既存問題を発見。[修正前](screenshots/summary-engine-wrap-before.png)を保存し、Pickerの縦サイズを確保。最大Dynamic Typeでは横並びが詰まるため、AppleのAnyLayoutを使って選択値のstateを保った縦並びにし、固定footerの説明をscroll領域へ移した。文言・機能を削らず、生成ボタンは下部に維持。

| 実装画面 | 検証 |
| --- | --- |
| [通常 Light](screenshots/summary-modes-light.png) / [Dark](screenshots/summary-modes-dark.png) | 生成mode/詳しさ/engine/送信同意/料金注意。生成未実行 |
| [最大Dynamic Typeのmode](screenshots/summary-modes-largest-type.png) | label/値/説明を縦配置し、scrollで到達可能 |
| [最大Dynamic Typeのengine](screenshots/summary-engine-largest-type.png) | engine名と説明が重ならず、全文をscrollで読める |

`summary-modes.e2e.ts`は高速/高精度/標準の切替、詳しさ不変、元summary/原文不変、jobを作らないこと、engineと説明のboundsが重ならないことをassert。通常サイズでPass（最大文字サイズは手動Simulator確認）。`markdown-replacement.e2e.ts`も2件再実行Pass。実VoiceOver読み上げや実機IME変換を検証済みとはしない。確認後、Simulatorの文字サイズ/appearanceを標準Large/Lightへ戻した。

以下は前回の画面検証:

大きなデザイン変更はしていない。モノトーン、フラットな本文、ブランド、余白、上部の作成Menu、サイドバーのナビゲーション、下部composer、既存のLiquid Glass実装は維持。
今回の画面変更は要約診断への導線、再送時の課金注意、実処理段階の表示と、ネイティブ編集を妨げるmenuの修正。

## 同じ合成fixtureでの比較

画像は実行中の専用Simulatorを撮影。生成モックアップではない。時計以外の同一データで比較し、要約本文や図解配置の意図しない変更は見られなかった。

| | Before | After |
| --- | --- | --- |
| 要約入口 Light | [画像](screenshots/summary-before-light.png) | [画像](screenshots/summary-after-light.png) |
| 図解シート Dark | [画像](screenshots/summary-before-dark.png) | [画像](screenshots/summary-after-dark.png) |

固定PNGだけで読ませず、既存の「全文」でネイティブ本文を開けること、PNG共有、Light/Dark、原文/読みやすい文字起こしの可逆切替、編集内容の反映と再起動をE2Eで確認。
[最大Dynamic Typeのnative全文](screenshots/summary-largest-type.png) も確認した。紙面のPNGは白地の出力として既存仕様を維持し、Darkでは周囲のnative UIが対応する。

## 日本語編集

- 読み取り時は従来どおりブロック/表セルをtapして編集。全体ソースへの切替は読み取り行の長押しから維持。
- 編集中はUITextViewのnative選択menuを親のSwiftUI menuが奪わない。選択長・確定した本文を保持。
- 日本語、長文paste、絵文字、結合文字、離脱と再起動、太字/斜体、箇条書き、表セルを確認。[編集後の復元](screenshots/edited-list-table.png)。原文と対象以外の全MarkdownもSQLiteで照合した。
- 実機キーボードのmarked text/候補操作は未検証。自動pasteの成功をその代替としない。

## 図解の正確性と互換性

不確かな数量・条件を完成品にせず、根拠が一致しないJSONは拒否する。既存保存JSONを削除/書き換えず、検証できない古い図解は原文の抜粋/全文へフォールバック。
表示サンプルは図解の4種類の構造を維持しつつ、否定・比較・未確定の文言を原文に合わせる。実際のAI生成と称しない。
再検証で [表示サンプル](screenshots/sample-diagram-light.png) と [nativeの図解/引用](screenshots/diagram-evidence.png) を確認した。長い画像の下端はスクロールと「全文」から読む既存構造を維持。
数値/意味の全体を決定的に証明できるとはしない。[レビューの制限](B_CODE_REVIEW.md) も参照。

## 残る確認

Ask AIの [Light](screenshots/ask-ai-light.png) / [Dark](screenshots/ask-ai-dark.png)、workspaceの [Light](screenshots/workspace-light.png) / [Dark](screenshots/workspace-dark.png)、[Journal Dark](screenshots/journal-dark.png) を専用Simulatorで撮影した。4件のE2Eでcomposer/サイドバー/3タブ/週次カレンダーとDarkの可読性を確認。これら3画面の変更前画像とJournal Lightの保存画像は今回採取していないため、要約以外のBefore/After比較まで完了したとはしない。

Ask AIの実モデル長文、ジャーナル・workspaceの全操作、実VoiceOver読み上げ、実機Reduce Motion、iPad/折りたたみ端末、OS中断時の全画面、課金後のネットワーク障害UIを網羅したわけではない。画面ごとの最終自動検証は [C](C_TESTS.md) に記載する。Liquid Glassの新規追加・撤去はしていない。
