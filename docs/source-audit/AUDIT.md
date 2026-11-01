# Memora 横断監査・統合改善

基準日: 2026-10-31。開始HEAD・origin/main・github/mainはいずれも `7ba0305e285706108525c10b5d1a2dc3f4b1a913`。開始時の作業ツリーは空。データ消去、設定リセット、ブランチ変更は行わない。

この文書の「確認」は特記しない限り静的コード確認。シミュレーター、ホストの実コードテスト、外部サービス、実機の証拠は VALIDATION.md に別記する。全画面のコードインベントリは [SCREENS.md](SCREENS.md)。部品を含む列挙であり、全画面を端末で操作したという意味ではない。

## 機能・画面・データの接続（着手前）

| 機能/主画面 | データ/保存 | 検索・AIとの接続 | 空/読込/失敗/オフライン/復元の監査 |
|---|---|---|---|
| Journal/Home、日別詳細、日記編集 | LifeLogEntry・SQLite、DraftStore | 個人検索・AI権限あり | 一次スクロール維持。クラウド非接続時は理由表示。端末操作未確認 |
| Library、全記録、選択・移動・削除 | Meeting・ProjectSource、SQLite＋ファイル | Meeting全文検索、ProjectSourceはタイトルのみ | 検索/選択中composer非表示。ソースは通常3件のみ＋全件導線 |
| Projects、SpaceDetail、参考資料、プロジェクトチャット/履歴 | MemoraSpace、同一資料へのprojectID | ProjectSearchIndex FTS＋ProjectContextBuilder、ページ/時刻引用 | 共有は読取専用。プロジェクト変更時に非同期結果を無効化 |
| 録音/録音詳細/Transcript、録音機ハブ/音声取込 | Meeting＋MediaFiles | 転写/要約/タスク、AskAI | 中断録音回復あり。取込後は手動転写。失敗時原音保持 |
| ProjectSource詳細、PDF表示、画像/Office QuickLook | ProjectSource＋WorkspaceFiles | 抽出本文はプロジェクトAIで読める | 抽出失敗/再試行あり。本文ローダー状態あり。要約/資料単位AI導線不足 |
| YouTube、VideoTranscriptImportSheet | ProjectSourceメタデータ＋人工Meeting | 字幕は別Meetingの転写として参照 | メタデータを本文と偽らない。字幕手入力が主導線。旧リンク保持が必要 |
| メモ/ノート編集、文章中リンクカード | MeetingまたはProjectSource、DraftStore | InlineLinkSession独自の取得/要約 | 本文と要約が混在しうる。取得と生成が別操作 |
| AskAI、QuickAI、添付、会話履歴、@、承認/質問カード | AIConversationSnapshot/AIHistory/添付ファイル | Meeting中心、グローバルsource検索はタイトル | 一添付、原文先頭制限、URLは独立カード。会話復元は権限を復元しない |
| 生成文書/資料一覧/詳細、PDF/PPTX出力 | MemoraDocument、会社テンプレート原本 | ローカルproject文脈/成果物provenance | 外部送信許可未定義の文書をcloudへ流さない。書式保持 |
| 要約シート/履歴/テンプレート/カタログ | TemplateSummary、PendingSummaryJob | MeetingSummarizer、タスク抽出 | 自動は候補テンプレート選択。中断cloud課金処理の自動再送を防止 |
| Tasks/編集/通知/出典、People/詳細、週次レビュー | tasks、人物、文書、関連recordID | 根拠レコードから構築 | Home NavigationStack。機密/人物許可を継承。回帰対象 |
| 共有拡張/共有Inbox/再取込、ファイルOpen In | App Groupキュー→SQLite | 共有audioはProjectSource、通常audioはMeeting | キュー再送重複抑止あり。保存先消失時は保持。取込経路に差異 |
| Marketplace、skill/template/connector詳細・全件・管理 | カタログ/SQLite、Firebase REST | AskAIとconnector hub共有 | 接続なしで公開数・投稿を捏造しない |
| Settings（12トピック）、AIモデル/同意/ライセンス | 設定UserDefaults、鍵Keychain、records SQLite | BYOK/端末/未接続サービス | 非実装サービスは非接続表示。勝手にAPIキー/権限を追加しない |
| 個人/チーム切替、共有project/record | TeamBackend/CloudKit snapshots | 受信共有はreadonly | 未構成backend拒否。workspace generationでA→B→Aも無効化 |
| バックアップ/復元/ゴミ箱/状態ギャラリー | SQLite batch＋安全なファイル参照 | 復元中書込停止、索引は派生 | 新フィールド任意追加、旧ID/ファイル参照不変が必須 |

## 入口×形式×保存範囲×検索×AskAI（着手前）

| 入口 | 形式 | 保存範囲/原本 | 検索 | AskAI | 矛盾 |
|---|---|---|---|---|---|
| ProjectSourceAddSheet | Web URL | 個人project、URL | title/global、本文取得後project全文 | 手動取得後projectのみ十分 | 保存と取得が別 |
| 同上 | YouTube URL | 個人project、URL/metadata | title | metadataは根拠にしない | 字幕は人工Meeting |
| 同上 | PDF/画像/Office/txt/md | project、原本＋抽出JSON | project FTS、global title | project本文、global read先頭 | PDF20/OCR3ページ制限 |
| 同上 | audio | project Meeting＋音声 | Meeting全文 | 手動転写後 | 他形式と異なる処理 |
| 同上 | local video | document原本 | title | 非対応 | 音声未抽出 |
| 録音機/＋import/Open In | audio | 個人/visible project Meeting | Meeting全文 | 手動転写後 | 自動転写されない |
| 共有拡張 | URL/各file/text | 選択project、キュー→source | title/project抽出 | source対応範囲 | 通常audioとは別構造、Web未取得 |
| メモ/日記の文章中URL | Web | 文章の独立リンクカード | 挿入した要約のみ | 文章としてのみ | 原文・要約・URLの関係が消える |
| AskAI直接file | PDF/画像/Office/txt等 | 会話の添付コピー | 先頭60k chars | 同じ質問のcontext | 一添付、長文後半・音声動画不可 |
| AskAI直接URL | Web | composer内カード、恒久保存なし | なし | 挿入後の要約 | 送信したURLだけでは原文を読めない |
| Library | source | 分類なしsource表示可 | title | global read_record | 分類なし新規source入口なし |

## 原因・修正優先度

| ID | 優先度 | 静的に確認した問題/原因 | 修正方針 |
|---|---|---|---|
| S01 | P0 | addProjectLinkはWebをunavailableにして終了 | 明示的な追加で安全取得→抽出→要約を共通経路へ |
| S02 | P0 | file/share/recorder/attachmentに個別分岐 | SourceIntakeで分類・抽出を共用、保存先ごとのpermissionは維持 |
| S03 | P0 | PDF first20/OCR3、page12k、text512KB | ページ単位、全ページ逐次OCR、byte/page予算と正確なcoverage |
| S04 | P0 | source本文はglobal検索で未検索、read_record先頭16k | FTS/チャンク検索をglobalとLibraryへ接続、queryに合う箇所を読む |
| S05 | P0 | automaticCandidatesから固定見出し選択、記録なし多数 | 内容適応型を既定に、手動template/length/会議task抽出は維持 |
| S06 | P0 | 転写なしmedia source、音声Meetingも手動開始 | 既存端末転写を自動起動、video音声track抽出、音声なしは明示 |
| S07 | P0 | 新YouTube字幕まで別Meetingを新規作成 | source本文へ直接保存。旧videoTranscriptMeetingIDの読取保持 |
| S08 | P1 | source詳細にsummary/AskAI統一導線なし | summary優先、原文開示、ページ/時刻/URL/AskAI |
| S09 | P1 | 中断した新sourceのpending/processingと要約が未分離 | extraction/summary別状態、指紋、有限retry、cloud自動再送なし |
| S10 | P0 | 会話添付を全体に保存すると情報漏洩 | 会話限定のまま即参照、明示保存のみLibraryへ |

## 変更しない保証境界

- record/Meeting/MemoraDocumentの全置換・ID再採番はしない。SQLite document内のoptional追加で旧データをdecode可能にする。
- チーム未接続を個人保存へフォールバックしない。cloudAI/off/機密/consent、workspace generation、request fingerprintを実行前後に検証。
- 外部資料内の命令は資料本文。ツール権限・承認・システム指示として使わない。
- YouTube任意公開動画の字幕取得は保証できない。公式API downloadには編集権限が必要（[公式仕様](https://developers.google.com/youtube/v3/docs/captions/download)）。スクレイピング/動画downloadを追加しない。
- 実機・課金provider・YouTube所有者OAuth・CloudKit/teamの未構成部分はテスト用成功表示で代替しない。

実装後の差分・互換性・テスト・制約は IMPLEMENTATION.md / VALIDATION.md に記録する。

## 実装中のシミュレーターで再現した問題

以下は静的推測と区別する。修正コードとホスト試験の成功は、LLM/実機の再現試験成功を意味しない。

| ID | 再現した問題 | 原因と変更 | 検証境界 |
|---|---|---|---|
| R01 | IANA Web記事の要約に原文にない疑問文 | 端末内の会議用questions schemaが資料にも使われた。資料専用topic/points schemaに分離 | iOS build成功。最終版の同記事再取込で要約成功・今回の出力に不当な疑問なし |
| R02 | 原文を質問中に要約が更新されるとcontextChanged | 資料全体の等価性で検査していた。本文参照/原本/所属/権限等を比較し、要約だけの更新は許容 | production identityの変更許容/拒否テストPASS。最終live完走は未確認 |
| R03 | 短い記事の端末内再要約でcontextTooLarge | topic再要約の狭いwindow工程を撤去し、各区間の要点から概要を構成。schemaの話題/要点件数も制限 | build成功。最終版の同記事自動要約が成功。長大/他genreの生成品質は追加確認が必要 |

| R04 | AskAIがドメイン表記を変形し、内部方針を回答に混ぜた | 固有名詞/否定・条件保持をsystem指示へ追加。実行指示と資料contextを分離 | 表記保持は途中版で確認。最後の分離変更はbuild/関連host検査成功、最終生成は未確認 |

実装後の入口表・互換性は [IMPLEMENTATION.md](IMPLEMENTATION.md)、操作比較は [COMPARISON.md](COMPARISON.md)、現在の結果と未確認は [VALIDATION.md](VALIDATION.md)。

## P1統合時に静的コードで確認した追加問題

以下は実機での再現報告ではない。実装経路と限定host検査で確認したもの。

| ID | 問題と原因 | 修正 | 検証境界 |
|---|---|---|---|
| S11 | 原本登録後、準備job開始前の終了でpendingが残る。復旧処理はprocessingのみ対象 | 起動/復元/取消後に、live jobのないpendingも再試行状態へ戻す | production SQLiteとlive queue/rollbackのhost検査。実OS強制終了は未確認 |
| S12 | 会話添付viewerがAI用の有限抜粋を原文として表示 | 全抽出ブロックを遅延表示し、実ページ/時刻へ共通viewerを再利用 | iOS buildと静的レビュー。追加UI実操作は未確認 |
| S13 | 解析結果の再利用はmemoryのみ。再起動で転写/OCRを再実行 | 上限付きSQLite派生cache、原本hash/形式/用語集/schema/OS/localeで再検証 | 別instance再起動/破損/失効/削除競合のhost検査。端末認識器はfixture |
| S14 | 添付を根拠に答えても、回答・履歴に原本の位置への参照が残らない | 実送信抜粋に限定した添付引用をoptional保存。予算で欠けた抜粋・不正番号はリンクにしない | production prepare/selection/codec検査。追加UIの実操作は未確認 |
| S15 | PDFの取消/時間制限後に先頭からOCRをやり直す | hashで結んだ連続ページcheckpointと、時間制限時の明示的継続 | production PDFKit/Vision/SQLiteの取消/再開/再OCR抑止/削除失効をhostで確認。iOS実機は未確認 |
| S16 | sourceは再要約の形式/長さ/AIを資料単位で選べない | その他メニューの任意設定とSQLiteへのoptional保存。削除済み選択へフォールバックしない | production解決/受入れ/保存と13競合のhost検査。追加UI/実AI品質は未確認 |
| S17 | 要約開始時に成功原文参照まで上書きし、失敗後に古い要約の出典が新本文に見える | summaryAttemptTextReferenceを分離。成功時のみsummaryTextReference更新 | 実SQLite/本文読込とfixture要約器の失敗→再試行で検証。過去に失われた参照は推測しない |
| S18 | PDFに文字layerがあるとOCRを省略し、画像内の文章が抜ける | 画像XObject/入れ子Formの候補ページをOCRし、原文保持と保守的な重複除去 | 実PDFKit/Visionで24ページ目の混在本文・FTS引用をhost確認。iOS実操作は未確認 |
| S19 | OCR例外時も完了checkpoint/完成cacheへ保存し、一時失敗が再試行で直らない | OCR失敗ページを区別し、完了保存を避け、明示再試行を追加 | 例外注入→実OCRで失敗ページの復旧、実SQLiteの再試行保存/完成cache回避。画面操作は未確認 |
| S20 | PDFのbyte上限確認前に巨大な本文を単語/位置索引/チャンクへ展開 | UTF8/JSON保存量の下限を先に確認し、超過ページから未解析扱い | 静的レビューとiOS build。OS内部のPDFKitメモリ/電力は未計測 |
