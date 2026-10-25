# UI/UX確認

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
