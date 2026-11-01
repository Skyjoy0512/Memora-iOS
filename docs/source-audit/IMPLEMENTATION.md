# 実装と互換性

対象: `7ba0305e285706108525c10b5d1a2dc3f4b1a913` からの追加変更。2026-11-01。

監査の着手時状態は [AUDIT.md](AUDIT.md)、画面の静的棚卸しは [SCREENS.md](SCREENS.md)、実行証拠と未確認項目は [VALIDATION.md](VALIDATION.md)。

## 共通の取り込み経路

`SourceIntake` が形式を判定し、`SourceProcessingQueue` で画像/PDF/音声処理の同時実行を抑える。ライブラリ、プロジェクト、Open In、共有Inbox、AskAIの添付は同じ抽出処理を使う。保存と権限は入口ごとに明示的に分ける。

- 個人・プロジェクト: 既存 `ProjectSource` を拡張。SQLiteには本文ファイルの参照を保存する。
- 会話: `AIAttachment` の最大10ファイル。URLは安全に取得した本文スナップショットまたはPDF原本を会話の添付フォルダーへ保持。全プロジェクトへの公開・登録はしない。
- 「ライブラリに保存」で初めて恒久資料へ登録する。取得済みのWeb本文は再取得しない。保存完了は要約を待たずに返し、model所有の既存jobで要約する。元URLと表示名は最初のSQLite登録に含め、解析中の後付け更新によるsnapshot失効を避ける。
- 旧録音は `Meeting` のまま。新規ファイルを人工的なMeetingへ変換しない。既存recordID、projectID、動画の旧字幕Meetingリンク、引用は維持。

`ProjectSource` の追加項目はすべてoptional。原本/URL・タイトル・種類・取得日時・本文/字幕JSON・ページ/時刻・解析範囲・要約・要約対象本文参照・失敗理由・履歴を保持する。ファイルSHA指紋、正規化URL、既存privacyを再利用する。旧データの一括書換えやID再採番はない。

## 入口×形式×保存範囲×検索×AskAI（実装後）

「共通解析」はコード経路の接続を表す。全組合せの端末試験済みという意味ではない。

| 入口 | 形式 | 保存範囲/原本 | 検索 | AskAI |
|---|---|---|---|---|
| Library＋、参考資料＋ | URL/Web/YouTube | 個人libraryまたは選択project、元URL | 抽出本文FTS・title・summary | 許可範囲の根拠抜粋 |
| 同上 | PDF/画像/Office/txt/md/srt/vtt | 同じsource、原本保持 | 同じ全文経路、page/time保持 | 同じ抽出JSONを参照 |
| 同上/録音機import/Open In | audio/local video | 同じsource、原音/動画保持 | 転写後の本文 | 転写時刻、音声のみの理解 |
| 共有拡張→Inbox | URL/file/text | 指定保存先、キューID重複抑止 | 同じsource検索 | 同じ許可検証 |
| 日記/メモの文章中URL | URL | 明示した追加で共通source | 元記事の本文 | 元sourceを参照 |
| AskAI直接URL | Web/PDF/所有者YouTube字幕 | その会話の添付のみ | 質問に応じ全文から抜粋 | 直ちに質問のcontext、添付から原文へ |
| AskAI直接file | 上記対応形式、最大10件 | 会話添付コピー | 全解析本文から関連部分を選択 | 複数添付を文書名/page/timeとともに渡す |
| 会話添付の「ライブラリに保存」 | URL/file | 明示保存、project指定なしはlibrary | sourceとして同じ検索 | 保存後は通常の許可範囲 |

## 取得・解析・要約の分離

- Web: DNS/実接続アドレス固定、危険URL/redirect再検査を維持。HTMLは既存のbounded scannerで抽出し、author/dateも保存。JavaScript実行、ログイン回避、paywall回避なし。常に「取得した部分」の扱い。PDF応答はMIMEとmagicを確認し原本保存後にPDF経路へ。
- PDF: 全ページを逐次処理し、文字のないページだけ端末OCR。先頭20ページ/OCR3ページ/ページ12k文字制限を撤去。ページ番号、OCRページ、読取不可ページ、上限で未解析のページを区別。検索は保存可能な全文を対象とし、旧project索引の2M文字予算で資料後半を落とさない。
- 音声/ローカル動画: 実際の音声trackを検査、M4Aへ一時変換、既存端末SpeechAnalyzerへ。時刻付き転写を保存して要約。音声再生は既存AVAudioEngine、動画再生も既存音声sessionの所有権に従い録音を優先する。音声trackなしを映像理解の成功にしない。自動取り込みでcloud転写は起動しない。
- YouTube: 既存公式metadata。字幕は別Keychainの所有者OAuth/PKCE/stateと公式captions.list/downloadのみ。権限・captionなしは動画/字幕fileを案内。手入力は最後のdisclosure。スクレイピングやYouTube動画downloadなし。
- 要約: `content.adaptive` を自動既定に。cloudは必要な見出しだけを生成、端末内の資料要約は話題・原文の要点専用schema。会議のdecisions/actions/questions schemaを資料に強制しない。明示的な会議/業務templateと詳しさ設定は従来の要約シートに残す。
- 原文と要約は別保存。要約対象の本文参照が一致すれば重複生成しない。再要約は原文ファイルを読むだけ。外部AIの既存同意/BYOK/機密制限を実行前後に検証。

## 検索・引用・アクセス

Libraryと参考資料の検索をtitleだけから本文FTSへ接続。待機中は空結果を確定表示しない。AskAIのglobal/project/source単位で、既存の `ProjectSearchIndex` と `ProjectContextBuilder` を再利用。各資料の候補を全体で再順位付けし、追加順の先頭8件で打ち切らない。

回答には実際に渡した本文の出典を保持する。保存済み資料の出典からPDFページ、音声/動画の再生位置、Web本文へ戻る。会話添付は添付メニューから原文を開ける。本文の命令はsystem指示・tool権限にしない。回答用の実行指示はsystem側に置き、資料contextへ混ぜない。履歴はgrantを復元せず、source/attachment由来の回答をcloudへ再送する際のprovenanceを未検証として扱う。

workspace世代・source snapshot・project snapshot・設定revisionで非同期結果を検査。原文を送る質問では、要約完了だけを本文の変更とは判定しない。本文/所属/権限の変更は失効する。A→B→Aも失効する。チームbackendが未接続の間はチーム保存・参照を拒否し、個人保存へ流さない。共有資料の受信は既存の読取専用画面のまま。

## 中断・重複・履歴

- source準備はmodel所有のsingle flight。画面を閉じても同一IDへ重複dispatchしない。削除/ワークスペース切替はcancelし、遅延結果を適用しない。
- 保存登録が失敗すればコピーをrollbackし、元file/Inboxを保持。保存後に画面の文脈が変わった場合も、登録済みの原本を削除しない。
- 処理中断後のsource/summaryは失敗と再試行へ。外部課金処理を起動時に勝手に再送しない。iOSで常時background完走を保証しない。
- 同じURL/指紋は同じ保存範囲内で再利用。会話から保存するPDFもURL重複判定に含める。異なるprojectを勝手に統合しない。
- `SourceExtractionCache` は会話/通常資料/remote PDFで共通。SHA-256と拡張子、音声/動画では用語集も照合し、コピー後も解析成功結果とpage/time/coverageを再利用。同じ内容の同時解析はsingle flight。解析前後にファイル変更を検査し、失敗・本文なしはcacheしない。保存や外部AI送信の許可はcacheとは別に従来どおり検査する。
- 原文更新は直前最大3世代の原本/本文/要約、再要約は最大3件の要約を保持。永久の監査ログではない。

## 制約・未解決

- 解析cacheは揮発性（最大6件・合計12MB、1結果4MB以下）。再起動・退避後や用語集変更時の再解析は残る。会話添付の解析本文の永続化は未実装。保存済みsourceの本文JSONは従来どおりSQLiteの参照先へ永続保存する。
- 原本50MB/source領域・会話添付領域はそれぞれ500MB、PDF最大2000ページ・抽出JSON約8MB・180秒、text4MB。超過分は未解析として保持・表示。これより大きい資料の分割取り込みUI、ページ単位の中断位置からの継続は未実装。
- OCRは文字のみ。混在ページ（文字layer＋図中文字）、表の構造、数式、映像の意味を保証しない。画像は先頭frame、Officeは既存の抽出可能部分。
- 検索はローカル字句FTS。意味検索や全資料を同時にLLMへ渡す方式ではない。回答の根拠抜粋と件数はmodel予算で有限。
- 会話添付のpage/timeは回答contextに含むが、回答文中の任意のpage/timeを添付viewerの位置へ直接結ぶ完全なアンカーは未実装。保存済みsourceの引用は位置へ遷移する。
- 新規sourceからタスクの自動登録はしない。既存Meetingの会議要約・タスク抽出は保持。sourceに対するタスクの出典型を拡張する作業は残る。
- 新sourceの要約は設定中のAskAIモデルと要約の詳しさを使用。資料ごとの任意業務template選択UIは追加していない。既存Meetingの手動template機能は保持。
- OAuth client設定・Google審査/権限、cloud AI、team backend/CloudKitは実環境の構成が必要。架空の接続やfixtureを本番成功にしない。
- 実機の音声認識資産、長時間mediaの電力/メモリ、全415 viewの操作、team実環境、課金providerは別途受け入れ検証が必要。検証状況は次の文書を参照。
