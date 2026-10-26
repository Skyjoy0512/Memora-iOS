# OSS比較・2026-10-27

GitHub APIのmain/default branch HEAD、最新release、固定SHAのLICENSE・manifest・代表ソースを取得した。
取得結果と各ソースのURL/SHA-256は [oss-evidence.json](comprehensive-improvement/oss-evidence.json)。
`releases/latest` はmonorepoの特定パッケージのreleaseであり、全製品の版とは限らない。
取得失敗は証拠JSONに残す。最終push日ではなくcommitの日時を比較する。
表の「iOS可」はmanifest上の最低OSが26以下という意味で、全候補のSwift 6実機ビルド成功を意味しない。
実行したPoC以外はソース検討まで。スター数による採否判断、ライセンスを外した転載はしない。

## PowerPoint

| 候補・確認版 | ライセンス / 主な依存・環境 | 重複・利点 / 注意 / 判断 |
| --- | --- | --- |
| [PptxGenJS](https://github.com/gitbrent/PptxGenJS) 4.0.1 | MIT、Node/browser、JSZip/image-size/https。Apple Silicon Node 22で実行 | PPTXWriterの高度な図表を比較する開発用エンジンとして採用。8枚でテキスト、native表、棒/折線/円、図形/線、写真contain、master/theme、ノートを生成。実行約40msは単発fixture値。iOSへのNode同梱はしない。Workersでの実行・CPU/メモリ上限は未検証。本番採用は保留 |
| [office-kit/pptx](https://github.com/office-kit/pptx) npm 0.28.0 | MIT、Node >=22.18 / browser、fflate。GitHub latestは別パッケージ`pptx-dev@0.14.4` | 既存PPTXをload、token置換、slide複製、見出し/ノート/画像/グラフ値を変更し9枚で再読込。原本bytes不変を確認。0.xでAPI成熟度に注意。日本語文字列は保持、実フォント/未知OOXML/企業書式の忠実度は保証しない。開発時PoC採用、本番保留 |
| [Presenton](https://github.com/presenton/presenton) electron-v0.9.12-beta | Apache-2.0、Python >=3.11,<3.12 + Next/ブラウザ、FastAPI/sqlmodel/mem0/fastembed/python-pptx/LLM SDK等 | HTMLレイアウトと構成/テンプレート抽出の設計参考。全体はiOSに直接適合しない。LLM呼出、画像取得、フォント、headless renderer、サーバー保守が増える。今回はインストール・起動せず、コード移植なし。本番不採用 |
| [Open XML SDK](https://github.com/dotnet/Open-XML-SDK) 3.5.1 | MIT、.NET、DocumentFormat.OpenXml.Framework等 | Office構造の高度な検査/編集に有力。描画エンジンではない。.NET未導入のため実行PoC未実施。将来CIのschema検査候補、アプリ依存にしない |
| [python-pptx](https://github.com/scanny/python-pptx) 1.0.2（インストール版） | MIT、Python/lxml/Pillow/XlsxWriter | 読込専用の相互運用検査に利用済み。59枚とノート3件を読めた。高度なOOXML往復・レンダリングの保証ではない。app/CIの新規常設依存にしない |

PoC再現: 隔離ディレクトリに固定版を`--ignore-scripts`でインストールし、
`node tools/poc/pptx-engines.mjs <node_modules> <新しい出力先>`。
サーバー作成、LLM・有料API呼出、Nodeのアプリ組込は一切ない。
生成成功とMicrosoft Officeでの描画成功は別の検査にする。

## SwiftUI・入力・品質

| 候補 | ライセンス / 互換性・依存 | 置換対象・判断 |
| --- | --- | --- |
| [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) 1.19.7 | MIT、Swift tools 6.0、iOS13以上。UIView image strategyはhost appが必要。別製品にswift-syntax/custom-dump | 最優先のtest-only候補。現行Project.jsonのBitrig標準プロジェクトはnative XCTest target未提供。製品targetにテストframeworkを追加しない。ネイティブテストhost対応まで導入保留、Simulator証跡を別管理 |
| [Swift Navigation](https://github.com/pointfreeco/swift-navigation) 2.11.2 | MIT、main tools6.4、iOS15、Dependencies/Perception等 | NavigationStack/既存ルートを置換する必然性がない。mainのtools要件とreleaseを混同しない。全面移行不採用 |
| [TCA](https://github.com/pointfreeco/swift-composable-architecture) 1.26.2 | MIT、main tools6.4、iOS16、Swift6、多数のPoint-Free製品 | MemoraModel+Domainの全面置換は回帰面積が大きい。dependency増に見合わず不採用 |
| [ChatGPTUI](https://github.com/bryanrg22/chatgpt-ios-ui) 0.2.0 | MIT、Swift6.2 / iOS26、swift-markdown | 現行の部分利用・帰属を維持。UI全体の模倣/アセット転用はしない。ヘッダー/入力/IME/承認は既存を磨く |
| [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) 2.4.1 | MIT、SwiftUI、作者がmaintenance modeと案内 | MarkdownDocumentView/編集blockとの二重実装になる。新規採用しない |
| [Textual](https://github.com/gonzalezreal/textual) 0.5.0 | MIT、Swift6 / iOS18 | Markdown表示の将来比較候補。現在のblock単位編集と統合PoC未実施。移行保留 |
| [RichTextKit](https://github.com/danielsaidi/RichTextKit) 1.2.0 | MIT、Swift5.9 / iOS15、UIKit/AppKit | 高品質入力に有力だが`@`メニューと日本語IME/SQLite draft契約は単純置換不可。現行TextField維持、将来限定editorで評価 |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) 0.9.0 | Apache-2.0 + Runtime Library Exception、Swift6.2、cmark系 | parserを必要とする機能に限定。現行表示/編集の全置換をしない。例外条項と通知を維持 |
| [Shimmer](https://github.com/markiv/SwiftUI-Shimmer) 1.5.1 | MIT、SwiftUI | 短い状態文専用の既存ShimmerTextと重複。新規依存なし。Reduce Motionで静止を保つ |

サイドバー/空状態/オンボーディング/ログイン/ペイウォールはApple標準List/Form/Menu/
ContentUnavailableView/AuthenticationServices/StoreKitを優先する。見た目だけのOSSを各画面に
追加しない。SnapshotTestingによるLight/Dark・最大文字・キーボードの自動回帰はまだ未整備。

## AI・検索・録音

| 候補 | ライセンス / 環境 | 判断・既存との重複とリスク |
| --- | --- | --- |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) 0.12.1 | main LICENSEはApache/MIT移行中＋docs CC-BY-4.0。既存固定tagの通知を維持 | 現行MCPClientで利用継続。HEADを単一MITと断言しない。OAuth/transport/権限をSDK導入だけで解決済みにしない。版更新は別PoC |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) 0.17.7 | Apache-2.0、Swift6 / iOS17、CoreML・Nemo binary/resources | 既存固定版を継続。モデルdownload量/ライセンス/peak memory/熱を別評価。実機の省電力を未測定で主張しない |
| [WhisperKit / Argmax OSS](https://github.com/argmaxinc/argmax-oss-swift) 1.1.1 | MIT、Swift5.10 / iOS16、ArgumentParser、server optionでVapor等 | 別のモデル/話者分離候補。FluidAudio/Apple Speechと二重常駐しない。モデル実機比較未実施、導入保留 |
| [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) 3.32.3 | MIT、Apple Silicon / MLX | ローカルLLMの巨大モデル・メモリ・電池負荷。現行未接続表示を維持。追加モデルDLや常駐なし |
| [swift-transformers](https://github.com/huggingface/swift-transformers) 1.3.5 | Apache-2.0、Swift/CoreML/tokenizer関連 | tokenizer/context長の参考。モデルごとのlicense/量子化/メモリを別途確認。現行context budgetを優先 |
| [Preternatural AI](https://github.com/PreternaturalAI/AI) releaseなし | MIT、Swift5.10 / iOS16、Merge/NetworkKit/Swallow/SwiftUIXのbranch依存 | LLM抽象化と重複。再現性と依存数に難あり。本番不採用 |
| [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) 2.2.2 | MIT、Swift5.9 / iOS15、NIOはLinux条件 | Anthropic tool/SSEと重複。現行CloudAgentSessionを置換する利益のPoCがないため保留 |
| [MacPaw OpenAI](https://github.com/MacPaw/OpenAI) 0.5.3 | MIT、Swift5.10 / iOS13 | OpenAI互換プロバイダの差異/stream継続/DeepSeek独自設定に注意。既存CloudAIServiceとの限定比較候補 |
| benallfree/SwiftAgent | GitHub404、存在・license未確認 | 候補に見えても採用しない。証拠JSONにもエラーを保持 |
| [Mem0](https://github.com/mem0ai/mem0) ts-v3.3.1 | Apache-2.0、Python/TS、LLM/embedding/vector store | 本人が明示したmemoryだけを保持するMemoraの契約と異なる。推論による自動memory・有料埋込を追加しない。設計参考のみ |
| [Graphiti](https://github.com/getzep/graphiti) 0.31.2 | Apache-2.0、Python、graph DB/LLM | RAGに追加サーバー・DB保守を要求。個人端末内には過大。不採用 |
| [Vercel AI SDK](https://github.com/vercel/ai) monorepo latest: xai5.0.31 | LICENSE本文Apache-2.0（API NOASSERTION）、TypeScript/provider packages | tool loop/stream再開/structured outputの参考。Swift直接導入不可、サーバー構築しない。パッケージ単位のversion確認必須 |
| [OpenUI](https://github.com/thesysdev/openui) cli0.6.0 / [Open Intelligent UI](https://github.com/thesysdev/open-intelligent-ui) releaseなし | MIT、Web/React中心 | モデル出力を実行可能UIへ無制限変換しない。許可した型と検証済み値だけをnative描画する設計参考。JS UI runtimeの追加なし |
| [sqlite-vector](https://github.com/sqliteai/sqlite-vector) 1.1.2 | Apache-2.0、C/SQLite extension | 有料embedding API不要な検索候補。iOS static link/配布モデル/license/精度/サイズPoC未実施。まず現行FTS5の権限・日本語gram・candidate境界を維持 |
| [GRDB](https://github.com/groue/GRDB.swift) 7.11.1 | MIT、tools6.1 / iOS13、SQLite | LocalStoreの取引/部分更新を容易にするが、store/backup全移行は高リスク。現行codec計測が先。ライブラリ採用だけでは全件encode問題は解消しない |

## 認証・課金・将来バックエンド

| 候補 | ライセンス / 環境 | 判断 |
| --- | --- | --- |
| [Firebase iOS](https://github.com/firebase/firebase-ios-sdk) 13.1.1 | Apache-2.0、Swift6.2.3以上という現行案内、Auth/Google関連のみ選択 | 将来認証第一候補。SMSは別料金、Google OAuth/Apple capability/匿名→本人link/退会を設計。SDKを今追加して未接続を利用可能にしない |
| [Supabase Swift](https://github.com/supabase/supabase-swift) 2.55.5 | MIT、main tools6.4 / iOS16、Auth/HTTP/Realtime等 | Auth代替。無料枠の休止/DB・egress/認証設定の運用を比較。現行SQLiteをクラウドへ移す理由にはしない。SDKビルドPoC未実施 |
| [RevenueCat](https://github.com/RevenueCat/purchases-ios) 5.99.0 | MIT、Swift5.9 / iOS13、サービス利用条件は別 | entitlement/返金/通知運用を軽くするがサービス料金・追加データ共有がある。StoreKit2を第一候補にし、複雑化後に再検討。未接続のまま |
| [Hono](https://github.com/honojs/hono) 4.13.14 | MIT、Web Standard/Workers、TypeScript | 将来API gateway/rate-limit middlewareの候補。認可・原子的credit台帳を自動で提供するわけではない。設計のみ |
| [jose](https://github.com/panva/jose) 6.2.13 | MIT、WebCrypto、Workers対応環境候補 | 将来Firebase JWT/JWKS検証候補。issuer/audience/alg/期限/clock skew・cache・rotationを固定、未知鍵でfail closed。Workers実行未検証 |
| Apple StoreKit2 / AuthenticationServices | OS SDK、OSS license比較の対象外 | iOS26標準。Apple署名取引・復元/失効・購入中断と実ユーザー認証を別々に扱う。clientだけでcloud creditを配布しない |

許諾性の高いlicenseでも、商用利用では通知/特許条項/別モデル・フォント・画像の権利確認が必要。
SDKのMITと、そのSDKが接続するサービスの料金/利用規約は別。35候補を
manifestまで比較したが、全依存CVE・全API・全モデルのsecurity audit完了とはしない。
