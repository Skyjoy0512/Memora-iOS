# 取り入れたオープンソース

## ジャーナルの背景写真

背景用の写真4枚は[Unsplash License](https://unsplash.com/license)で配布される写真を同梱。背景は装飾であり、本人が訪れた場所や撮影した写真を示すものではない。ネット接続なしで表示する。添付のUnsplash+透かし入り画像は使用していない。

| プリセット | 配布元の画像 |
| --- | --- |
| 森 | https://images.unsplash.com/photo-1441974231531-c6227db76b6e |
| 湖 | https://images.unsplash.com/photo-1470770841072-f978cf4d019e |
| 緑の葉 | https://images.unsplash.com/photo-1497250681960-ef046c08a56e |
| 夕景 | https://images.unsplash.com/photo-1500534623283-312aade485b7 |

## コードと設計

| 名前 | 使い方 | ライセンス |
| --- | --- | --- |
| [LucideSwift 0.9.11](https://github.com/ajaxjiang96/lucide-swift/tree/0.9.11) | アプリ・ウィジェットの共通アイコン。対応表は `docs/LUCIDE_ICONS.md`。ライセンス全文はアプリ内リソースに同梱 | ISC |
| [yomiyasu v1.1.0](https://github.com/nanaism/yomiyasu/tree/v1.1.0)（nanaism） | 日本語を読みやすくする規則を要約・Ask AI・エージェントの指示文に取り入れた（`App/ReadabilityGuide.swift`） | MIT |
| [日本語の技術文書の書き方](https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d)（k16shikano） | 段落・推量・用語の規則を同じく取り入れた | Unlicense |
| [OpenDots](https://github.com/CopilotKit/OpenDots)（CopilotKit） | 常駐エージェント（名前・役割・指示・権限・定期的な見回り・作業記録）の設計を参考にした。コードはTypeScriptのため移植していない | MIT |
| [OpenMuse](https://github.com/CopilotKit/openmuse)（CopilotKit） | 目標の定期チェックと見える作業記録の考え方を参考にした | MIT |

## yomiyasuの取り込み版

- 確認日: 2026-10-08。タグ: `v1.1.0`。コミット: `c2ffae670994fec96daef92e0bc219f5c1923113`。
- 配布スキルの指針をMemora向けに要約して取り込んでいる。Pythonのlint／diffツールや、開発環境のスキル本体をインストールしたものではない。
- 主張・条件・確度の保持、短い見出し、議事録の発言者と担当者の区別、「こと」の整理、前後の限定の持ち込み防止を反映。
- Memoraの要約テンプレート・表形式と、選択的な太字・段落間の空行は維持する。推敲スキル固有の「変えたところ」などの出力欄は追加しない。
- 更新後に生成する文章に適用する。保存済みの要約・回答は自動で書き換えない。生成品質の比較評価は未実施。
