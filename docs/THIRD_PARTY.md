# 取り入れたオープンソース

## 話者分離と声の特徴量

- [FluidAudio 0.17.7](https://github.com/FluidInference/FluidAudio/tree/v0.17.7): 録音後の話者分離と256次元embedding生成。SDKはApache-2.0。`FluidAudio-LICENSE.txt`、FastclusterのBSD-2-Clause、VBxおよびNeMo関連のライセンス/NOTICEを `App/Resources/` に同梱。TTSフロントエンドの第三者告知も保存する。
- [Community-1 Core MLモデルのNOTICE](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/df2625ac79a7ac6b65ad868fee6d80f320da4232/NOTICE.md): pyannote、WeSpeaker、BUT Speech@FIT、Fluid Inference。Core ML変換による変更あり。対象モデルはCC BY 4.0。固定revisionの対象25ファイルだけを利用し、出典・LICENSE・NOTICE・PROVENANCEも取得/検証する。アプリには `Community1-LICENSE.txt` と `Community1-NOTICE.txt` を同梱し、設定の話者識別画面にも出典とリンクを表示。
- 対象モデルはSegmentation/FBank/Embedding/PldaRhoとパラメータ。legacyのwespeakerや、ライセンス未確認の追加モデルを自動取得しない。SDK本体とモデルのライセンスは別に扱う。
- 機能の制限・商用利用時の確認事項は `docs/PERSONALIZATION_IMPLEMENTATION.md` に記載。診療記録の適合性、本人識別精度、録音/共有の同意や法的有効性を保証しない。

## ジャーナルの背景写真

背景用の写真4枚は[Unsplash License](https://unsplash.com/license)で配布される写真を同梱。背景は装飾であり、本人が訪れた場所や撮影した写真を示すものではない。ネット接続なしで表示する。添付のUnsplash+透かし入り画像は使用していない。

| プリセット | 配布元の画像 |
| --- | --- |
| 森 | https://images.unsplash.com/photo-1441974231531-c6227db76b6e |
| 湖 | https://images.unsplash.com/photo-1470770841072-f978cf4d019e |
| 緑の葉 | https://images.unsplash.com/photo-1497250681960-ef046c08a56e |
| 夕景 | https://images.unsplash.com/photo-1500534623283-312aade485b7 |

## コードと設計

コネクタの公式ブランド画像と配布元は[コネクタの公式ロゴ](CONNECTOR_LOGOS.md)に記載。
各ロゴは各権利者の商標であり、接続先の識別に使用する。

| 名前 | 使い方 | ライセンス |
| --- | --- | --- |
| [MCP Swift SDK 0.12.1](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1) | リモートMCPのクライアント。ライセンス全文をアプリ内リソースに同梱 | MIT |
| [LucideSwift 0.9.11](https://github.com/ajaxjiang96/lucide-swift/tree/0.9.11) | アプリ・ウィジェットの共通アイコン。対応表は `docs/LUCIDE_ICONS.md`。ライセンス全文はアプリ内リソースに同梱 | ISC |
| [yomiyasu v2.3.0](https://github.com/nanaism/yomiyasu/tree/v2.3.0)（nanaism） | 日本語を読みやすくする規則を要約・Ask AI・エージェントの指示文に取り入れた（`App/ReadabilityGuide.swift`） | MIT |
| [日本語の技術文書の書き方](https://gist.github.com/k16shikano/fd287c3133457c4fd8f5601d34aa817d)（k16shikano） | 段落・推量・用語の規則を同じく取り入れた | Unlicense |
| [OpenDots](https://github.com/CopilotKit/OpenDots)（CopilotKit） | 常駐エージェント（名前・役割・指示・権限・定期的な見回り・作業記録）の設計を参考にした。コードはTypeScriptのため移植していない | MIT |
| [OpenMuse](https://github.com/CopilotKit/openmuse)（CopilotKit） | 目標の定期チェックと見える作業記録の考え方を参考にした | MIT |

## yomiyasuの取り込み版（初回1.1.0の記録）

- 確認日: 2026-10-08。タグ: `v1.1.0`。コミット: `c2ffae670994fec96daef92e0bc219f5c1923113`。
- 配布スキルの指針をMemora向けに要約して取り込んでいる。Pythonのlint／diffツールや、開発環境のスキル本体をインストールしたものではない。
- 主張・条件・確度の保持、短い見出し、議事録の発言者と担当者の区別、「こと」の整理、前後の限定の持ち込み防止を反映。
- Memoraの要約テンプレート・表形式と、選択的な太字・段落間の空行は維持する。推敲スキル固有の「変えたところ」などの出力欄は追加しない。
- 更新後に生成する文章に適用する。保存済みの要約・回答は自動で書き換えない。生成品質の比較評価は未実施。

## Ask AI 2.0の設計調査（2026-10-17）

[調査記録](ASK_AI_2_OSS_AUDIT.md)。bryanrg22/chatgpt-ios-ui（ソースMIT、素材は別条件）、
thesysdev/openui（MIT）、thesysdev/open-intelligent-ui（demo自体のlicense未確認）を設計比較した。
初回調査時点では設計参考のみ。その後chatgpt-ios-uiの `ChatGPTMarkdownView.swift` から
コード枠・tableWidths/行描画・引用枠/本文間隔を部分移植した（固定SHA `dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1`）。
対象: `AIResponseCodeBlock.swift`、`AIResponseTable.swift`、`AIResponseTableLayout.swift`、
`AIResponseMarkdownBlock.swift`、`StreamingMarkdownView.swift`。
Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors。MIT全文は
`App/Resources/ChatGPTUI-LICENSE.txt` に同梱。変更: 日本語、Dynamic Type、44pt操作、
モノトーン、コピーのキャンセル、既存incremental parser/出典リンク、列幅の上限補正。
Package、swift-markdown/cmark、ブランド画像、ChatState、OpenUI runtimeは導入していない。
OpenUIとopen-intelligent-uiのコード/画像/プロンプト素材は引き続き取り込んでいない。

## yomiyasu 2.0.1への統合（2026-10-18）

タグv2.0.1の実コミット `1bc21f9c8e6a55fc4ccd5a2c7dfe78a7b0d814c5`、MITを再確認。
Copyright (c) 2026 nanaism。全文を `App/Resources/Yomiyasu-LICENSE.txt` に同梱。
旧memoraブランチの更新意図から、時制・意味のまとまり・助詞と読点・補助動詞/形式名詞の規則を
既存のReadabilityGuideへ適応した。現在の発言者/担当の区別、条件・否定・確度、テンプレート/スキーマ保護は残す。
Ask AIの自然な会話と段落の指示も追加し、資料を命令として扱わない現行の安全指示は維持した。
Python/スキル実行環境は導入しない。実モデルによる文章品質のA/B評価は未実施。

## yomiyasu 2.3.0への指針更新（2026-10-24）

GitHubの最新タグとmainを確認し、両方の実コミット
`15244a1369c192d6b7e74963ee9709537fadf166`を固定した。
2.3.0の連用形名詞、専門用語/直訳、意味・確度・目的/理由の保持、提出前の原文との照合を
Memoraの指示へ適応した。会議では提案/合意/条件付き合意/記載なしと未定を区別し、
原文のない担当・期限・根拠を補完しない。テンプレート、スキーマ、引用の原文は保つ。
同梱MIT全文は上流と同じ。Pythonのlint/diff/check、hooksやCLIの性能改善は移植しておらず、
スキル全体がiOS上で動くとは扱わない。追加LLM呼び出しはなく、保存済み要約の自動再生成もしない。
