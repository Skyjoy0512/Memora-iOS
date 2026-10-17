# Ask AI 2.0 / iOS 26 — 監査と採用判断

2026-10-17。GitHub mainをfetchして `13af297`、ローカルmainは `f28116c` を確認。
差分は前回の通信モック統合・検証記録2コミットで、破棄/重複取込はしていない。
AGENTS、DESIGN、Project.json、NEXT_GENERATION_AI、ASK_AI_NEXT_IMPLEMENTATION/VALIDATION、
MONOCHROME_DESIGNと指定のSwiftファイルを確認した。DESIGNの古い4タブ記述より、
ユーザーの最新指示と実装のHome/Library/Ask AIを優先する。

## 後続の部分移植（2026-10-17）

以下の監査本文は初回時点の判断。その後、利用者の再現要望によりchatgpt-ios-uiのMITコードを
選択的に取り込む方針へ変更した。[部分移植記録](ASK_AI_OSS_POLISH.md)を現在の状態として参照。
OpenUI/demoのコード移植や全文フレームワークの置換は行っていない。

## 初回監査時点の実装と検証の区分

- 実装済み: ネイティブの3タブ/Glass/FAB、空白新規chat、ユーザーバブルと回答Markdown、
  @registry/Skills/IME保護/SQLite draft、添付解析と停止、録音/人物/プロジェクト範囲。
- 実装済み: CloudAgentSession/ストリーム受信/100msまとめ、IncrementalMarkdownCache、
  明示的なscroll-follow intent、長期メモリ/人物ID/出典/承認/予算/権限失効。
- 部分実装: NativeAIInterface v1の8種類。回答完了後にJSON全体を検証して表示。
  UIにtask/project/document/source IDの参照制限があり、古い履歴で操作権限を復活させない。
- 不足: agentStepsを保持しているが画面は実行中の一行だけ。コードブロックには専用コピーがなく、
  Markdown表はカード列。構造化UIの完成部品単位の早期表示とメール成果物の専用表示がない。
- 未検証: 実サービスA〜E全体、実機VoiceOver/メモリ/電力/大量データ。過去のhost/Simulator成功と区別。

## iOS 26移行

Project.jsonのproject-level deploymentTargetを26.0へ変更し、アプリ・Widget・Share extensionへ
共通適用する。target側の上書きはない。SQLite/Keychain/媒体/backup形式は変更しない。
既存のavailability分岐は一括削除せず維持する。App Intents/WidgetKit/ActivityKitのソースも維持。
環境はSwift 6.4 / iOS 27.1 SDK。Swift 6.2での実コンパイルやSwift 6 strict language modeの
全面移行とは区別する（既存projectの言語modeを維持）。新しい27専用APIは追加しない。

## chatgpt-ios-ui

対象SHA: `dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1` (2026-10-10)。
[ソース](https://github.com/bryanrg22/chatgpt-ios-ui/tree/dc6e6a52b14a67051f6534cc674cc32ddd9cb9d1)。
MIT。Package.swiftはSwift tools6.2/iOS26/macOS26、swift-markdown0.9+依存。
そのApache-2.0と推移依存cmarkのBSD系noticeが別にある。

確認: ChatGPTView、ChatState、ChatGPTMarkdownView/MarkdownDocumentModel、ComposerTextView、
VoicePresentationView/VoiceCloudField、WorkTaskPresentationState、PluginsDestination、
Examples/ChatGPTUIDemoのSnapshotTests、Tests/ChatGPTUITests、README/TESTING/THIRD_PARTY_NOTICES。

| 項目 | 評価 / Memoraへの適用 |
| --- | --- |
| ChatGPTView / ChatState / sidebar履歴 | 独立したmessages/draft/responseIDを持つ。丸ごとの導入は二重状態と独自rootを増やすため見送る |
| メッセージ・回答action | 平文回答+控えめなバブル、コピー/共有/再試行の配置を参考。既存実装を維持 |
| Markdown | AST/表/コードの描画は参考。Memoraのincremental cacheと出典リンクを捨てて置換しない |
| ComposerTextView | UIKitの実測高さは参考。ただし固定17pt/24行高とmarkedText保護不足があり、既存TextField/IME保護を維持 |
| scroll / keyboard | 毎回末尾へscrollする処理をそのまま導入しない。既存user intent/keyboard resize判定を使用 |
| voice / waveform / orb | 表示用のsilent fixture。実音声処理ではない。既存録音/VoiceGlowを保持し色とmotionを調整する |
| model / plugins / Work | action-outの考え方を参考。sample接続状態・許可選択を実サービスの権限として持ち込まない |
| Glass / transitions | ネイティブGlassとReduce Motionの利用を参考。既存navigation/FABを保持 |
| screenshot tests | 架空fixtureのLight/Dark/画面別snapshotと比較精度設定がある。Memoraの検証結果には換算しない |

直接Package導入はブランドKnot素材もbundleに入る。noticeがそのロゴの出所/許諾未確認を明記しており、
今回の採用対象にしない。個別移植ならMIT notice保持と素材排除が必要だが、今回はコードのコピーをせず、
UI設計の参考として独自Swift実装を既存viewへ追加する。新規依存なし。

## open-intelligent-ui

対象SHA: `6a4a0ba192ea285b3a5ed39dcc1295d7d4080d6f` (2026-10-15)。
[ソース](https://github.com/thesysdev/open-intelligent-ui/tree/6a4a0ba192ea285b3a5ed39dcc1295d7d4080d6f)。
調査時点でリポジトリ内LICENSE/COPYINGファイルとpackage license fieldが見つからない。
OpenUI本体のMITをこのdemoへ拡張しない。コード/画像/プロンプト例を転載しない。

ライセンス再確認（2026-10-17、`main` 現行ソース）: `LICENSE` は404、`package.json` は
`"private": true` で `license` フィールドなし、GitHubのファイル一覧にもライセンス表示なし。
現行でも再利用許諾は確認できないため、コード・画像・プロンプトの取り込み対象にしない。
同時に再確認した OpenUI 本体の `LICENSE`（MIT, `Copyright (c) 2011-2024 Thesys Inc.`）と
chatgpt-ios-ui の `LICENSE`（MIT, `Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors`）
は現行でも有効で、ソースコードの利用は可能（素材・フォントは別条件）。

README、package.json、src/lib/library.ts、layout/controls/media/chart、actions.ts、chat-storage、
api/chat、scripts/benchを確認。Node24/Next16/React19、OpenUI Lang1.0、Zod、KaTeX、
Lucide React、MapLibre、PostHog、OpenAI SDKなどが依存。サーバーと外部APIが必要な機能を持つ。

Layout/inputs/mediaに加え関数/式、HTML iframe、任意URL action、画像探索、地図/ルートまで実装する。
Memoraで必要なtask/資料/比較/進捗/出典を優先し、JS評価/任意URL/外部画像取得は導入しない。
localStorageの会話とページ状態は、MemoraのSQLiteと一時的な開閉状態へ役割を分けて実装する。
benchmarkは16例+8dashboardのmodel呼出し/検証/Light-Darkスクリーンショットを持ちfake実行も可能。
このbenchmarkやdemoを実行したとは報告しない。APIキーや有料処理は利用しない。

## OpenUI本体

対象SHA: `8d9c4c3b108a7b5352192a6a9d7327bdf7ea19b5` (2026-10-16)。
[ソース](https://github.com/thesysdev/openui/tree/8d9c4c3b108a7b5352192a6a9d7327bdf7ea19b5)。
ルートMIT、@openuidev/react-lang/lang-core 1.0.1もMIT表記。各依存/サービスは別条件。
lang-coreはci-info、react-langはlang-core/devtools/observabilityとReact/Zod peer依存。
インストール時telemetryとopt-in server runtime telemetryの説明がある。インストール/実行はしない。

確認: packages/react-lang Renderer.tsx/README/tests、lang-core README/package、component library、
action/stream APIとbenchmarks。Rendererはstream中のform操作を抑制し、Query更新中に既存表示を保持。
ElementErrorBoundaryも直近の有効childrenを保持する。Memoraでは完成部品のIDを安定させ、
部分JSONを実行せず検証済み部品だけを表示する独自の限定JSON方式へ適用する。
OpenUI Lang互換やDSL runtimeの搭載は主張しない。

本体の7シナリオbenchmarkは一度生成した同じASTを4形式へ変換したtoken数と固定60token/s推定を比較する。
Memora/iPhoneのFPS・メモリ・正解率の証拠にはならず、掲載の削減率を本アプリの成果に転記しない。

## 方針

SwiftUI/既存registry/SQLiteによる独自実装。OSSのSwift/Reactコード、商標・画像・プロンプト例は
取り込まない。新しいサーバーやAPI契約、JS runtime、テレメトリー、常時運営費を追加しない。
UIの開閉/選択はview-local、永続データ更新は既存tool/承認、表示用JSONは常に非信頼データとする。

[Apple Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)と
[Motion](https://developer.apple.com/design/human-interface-guidelines/motion)の設計原則も参照。
