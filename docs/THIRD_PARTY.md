# 取り入れたオープンソース

## 65型の資料生成仕様（2026-10-27）

[consulting-pptx-skill](https://github.com/carnot-tech/jinba-consulting-pptx-skill)
HEAD `e5f35e57e14d3998249a559c620a9286c95b4595`、MIT、Copyright (c) 2026 Carnot AI Inc.。
65型の対応、構成→型→検査の手順、禁止表現/数値照合の考え方をSwiftへ適応。
Python/Node/HTML実行基盤とブランド資産は同梱しない。MIT全文はConsultingPPTX-LICENSE.txt。
TRADEMARK.mdを確認し、他社名・広告・ロゴを生成プロンプト/資料に追加しない。
成果物の所有権と、配布する仕様由来のコード/文面のMIT告知を区別する。

設定最下部の「オープンソースライセンス」へランタイム依存/モデル/再利用文面を集約。
MCP 0.12.1同梱ライセンスの実文はApache-2.0/MIT移行告知を含むため、画面もその旨を表示する。

## 開発時だけの検証ツール（2026-10-27）

| 名前 | 用途・範囲 | ライセンス |
| --- | --- | --- |
| [PptxGenJS4.0.1](https://github.com/gitbrent/PptxGenJS/blob/v4.0.1/LICENSE) | 外部scratchのNodeでeditable PPTX生成を比較。アプリにNodeやコードを同梱しない | MIT |
| [office-kit/pptx0.28.0](https://github.com/office-kit/pptx) | 外部scratchで既存PPTX編集/複製/再読込。製品依存なし | MIT |
| [SnapshotTesting1.19.7](https://github.com/pointfreeco/swift-snapshot-testing/blob/1.19.7/LICENSE) | `tools/poc/SnapshotComparison`のMac画像比較のみ。固定SHA1488390b0735e726564b948bf08b384398bdab5c | MIT |

SnapshotTestingの解決済み依存は同ディレクトリのPackage.resolvedに記録。
swift-custom-dump/issue-reportingはMIT、swift-syntaxはApache-2.0 with Runtime Library Exception。
配布する場合はそれぞれのLICENSE/NOTICEを保持する。今回、vendorコードやbinaryはGitへ同梱せず、
Project.json/Appのランタイム依存と混同しない。各候補とモデル/画像の許諾は別に確認する。

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
| [LucideSwift 0.9.11](https://github.com/ajaxjiang96/lucide-swift/tree/0.9.11) | [Lucide](https://github.com/lucide-icons/lucide)由来のアプリ・ウィジェット共通アイコン。対応表は `docs/LUCIDE_ICONS.md`。ライセンス全文はアプリ内リソースに同梱 | ISC |
| [yomiyasu v2.4.0](https://github.com/nanaism/yomiyasu/tree/v2.4.0)（nanaism） | 日本語を読みやすくする規則を要約・Ask AI・エージェントの指示文に取り入れた（`App/ReadabilityGuide.swift`） | MIT |
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

## yomiyasu 2.4.0への指針更新（2026-10-25）

[最新リリース](https://github.com/nanaism/yomiyasu/releases/tag/v2.4.0)を確認。
annotated tag `d45383e66e09c6c179ab593a31c2624e8fbb81fb` の実コミット
`ae258d7a57b335673e30b88a018ae08d4f72c449` を固定した。mainのその後の変更はREADME整理のみ。
取り込み対象は、不自然な短い直訳語を文脈に合った呼び名にする規則、資料・依頼にない
主語／担当／通知先／依頼先を補わない照合、スライドの短い見出し・箇条書きだけの読点整理。
引用、条件、否定、専門用語、通常の本文、テンプレート・スキーマ・ページ順を保護する。
これらは既存の共通指示へ適応したもので、生成後に本文を機械的に書き換えるものではない。
上流のPython lint/diff/checkやインストール手順・フックは導入しない。追加API呼び出しなし。
同梱MITライセンスは上流と同一（SHA256 `79d802f15bc8caf67f1a83c1bdbe214ccb41a0a0275f9046b329b89c65ee1fca`）。
指示の組み込みはホストテストで検証。実モデルでの文章品質・意味保持のA/B評価は未実施。

## J-MeetEval (development evaluation only)

Copyright 2026 Nishika, Inc. Apache License 2.0. Pinned upstream code and public
synthetic benchmark data are under `tools/evaluation/vendor/jmeeteval`, including
its unmodified LICENSE and NOTICE. They are excluded from app targets. See
[the integration and exact revisions](JMEETEVAL_INTEGRATION.md).

## Live音声会話（2026-11-15）

[Volocal](https://github.com/fikrikarim/volocal)、固定コミット
`b731963bac43ab29ca430d7f0e55f7b843cc46e5`、MIT、Copyright (c) 2026 Fikri Karim。
VoicePipeline、SharedAudioEngine、SentenceBufferを日本語Live向けに部分移植。
共有AVAudioEngineとエコーキャンセル、文単位のストリーミング読み上げ、割り込み時の
世代管理を採用した。日本語の句読点・空白なし長文・Unicode書記素、再生完了の判定、
非同期の古い結果の拒否、ロック付き入力橋渡し、バッファ上限を追加した。

英語向けParakeet EOU / PocketTTSは同梱しない。音声認識は日本語のオンデバイスDictationTranscriber / SpeechAnalyzer、音声合成は日本語の
AVSpeechSynthesizerのPCM出力を使う。Liveの回答は端末内Qwenで生成し、APIへの
フォールバックは行わない。音声で承認カードの承認を代行しない。
MIT全文は `App/Resources/Volocal-LICENSE.txt`、設定のライセンス一覧にも掲載。

## Liveのローカル会話モデルと推論ランタイム

- [llama.swift](https://github.com/mattt/llama.swift/tree/2.10327.0)、2.10327.0、MIT、Copyright 2025 Mattt。
- [llama.cpp](https://github.com/ggml-org/llama.cpp/tree/b10327)、b10327、MIT、Copyright (c) 2023-2026 The ggml authors。
  公式XCFrameworkはSwiftPMの固定checksumで取得する。VolocalのLlamaContextを日本語・
  有界batch・UTF-8ストリーミング・キャンセル向けに変更した。
- [Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B)、Qwen Team / Alibaba Cloud、Apache-2.0。
  [bartowskiのGGUF量子化](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF)、
  revision `7d26695454df6de5fbcce2e58681e62dae06ce43`、Q4_K_S。
  重みはアプリに同梱せず、利用者のダウンロード操作後にサイズとSHA-256を検証して端末へ保存。
  固定値・保存場所・実機検証の境界は `docs/LIVE_CONVERSATION.md` を参照。

ライセンス全文はApp/ResourcesのLlamaSwift-LICENSE.txt、LlamaCPP-LICENSE.txt、Qwen35-LICENSE.txt。
