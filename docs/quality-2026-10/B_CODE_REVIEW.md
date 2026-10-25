# 総合レビュー：修正と残課題

基点 `23230af5e0356a1a5f7d8d4e72ed22b5d937d704`。これは全機能の品質保証完了報告ではない。
P0の実際の50秒事象は [A](A_SUMMARY_TIMEOUT.md) のとおり診断照合が残る。

## 修正した問題

2026-10-26追加（既存修正を置換・重複実装しない）:

| 優先度 | 観測した問題・原因 | 修正箇所と方法 | 回帰/残るリスク |
| --- | --- | --- | --- |
| P0 CI | 英語localeで旧monthラベルと現行日本語ラベルのequalityがSIGTRAP | 比較harnessのclock/calendar/UI契約を固定。両localeで全assert維持 | 実GitHub全6suite Green。[CI](CI.md) |
| P0 診断 | reasoning到着を初回本文として記録、複数requestのtoken区間が混同 | accumulatorの実本文/reasoning counterとrequestごとのTaskLocal ID | 重複request/usage/秘匿/仮想長時間のfixture。実50秒原因は未確定 |
| P0 性能 | 小さな本文deltaごとにAny dictionary alias/全文を再構築 | 独立append buffer、Anthropic index順を保持 | 本文一致・Unicode・snapshot・上限/切断・agent context保持。ホスト21試行比較 [H](H_SUMMARY_SPEED.md) |
| P0 要約 | 長文を逐次で処理、推論設定と出力長が分離されていない | 互換decodeの生成mode、レビュー済みDeepSeekだけopt-in設定/最大2並列、各送信前に権限/入力を再検査 | 本番通信matrix/実summarizerの順序・取消・部分失敗。実API速度/品質/料金はNot Run |
| P1 保存 | Keychain失敗でもlicense状態だけ有効化/解除 | 成功確認前のメモリ/設定変更を拒否、起動flag再計算、削除失敗も表示 | 失敗注入・再読込・期限・旧code保持 [I](I_LICENSE_STORAGE.md)。実Keychain OSエラー未検証 |
| P1 RAG | 弱い語句・数字/英語部分一致と重複chunkがcontextを占有 | confidence/anchor/複数話題補完とexact chunk dedup | 27問で混入0.519→0.167。まだ混入あり、意味の完全保証ではない [J](J_RAG_PRECISION.md) |

以下は前回修正の記録:

| 優先度 | 観測した問題・原因 | 修正箇所と方法 | 検証境界 |
| --- | --- | --- | --- |
| P0 | DeepSeekの非表示推論と反復JSONも2MiB総量制限に含め、本文前に拒否 | `CloudSSEEventDecoder`, `CloudStreamAccumulator`, `CloudTurnStreamReader`：wire/本文/イベントの上限を分離、要約では推論を保持しない、実deltaの活動通知 | 修正前fixtureで再現、修正後同一fixture PASS。利用者の実事象との一致は未確定 |
| P0 | JSON/SSEの終了検証が不一致、空・拒否・tool・lengthの混同 | `CloudAIService`, `CloudTurnStreaming`, `CloudSummaryResponse`, `CloudAgentTurnDecoder`：共通の検証済みdecoderへ集約 | プロバイダー別fixture、終端なしEOF・未完成tool・複数choice・不正型等 |
| P0 | 推論開始を永続化せず、再起動時に課金済みかもしれないジョブを再送し得る | `PendingSummaryJob`, `MemoraModel+SummaryGeneration`, `MemoraModel+BackgroundSummary`：開始前の原子的保存と要確認マーカー、開始済みジョブの自動再送禁止 | 実SQLite失敗注入・再読み込み。クラウド再送なし |
| P0 | 前景復帰時のUIKit猶予expiration、540秒待機制限 | `SystemSummaryBackgroundScheduler`, `MemoraModel+BackgroundSummaryTask`：OS制約と前景実行を分離 | scheduler fixture。実機OS配信未検証 |
| P0 | Foundation Modelsのtimeout等を準備不足に分類 | `FoundationModelFailure`, `OnDeviceSummarizer`：timeout/資産不足/未知生成エラーを区別、区間分割は一度だけ | SDKの実エラー型と区間制御fixture。実モデル未実行 |
| P0 | 「150人」の根拠が「50人」を支持する部分一致 | `GroundedQuantity`, `MeetingInfographic`, prompt：数値・桁区切り・符号・単位・日時をトークン単位で照合。関係・否定・条件があるときは保守的に原文句の保持を要求 | 人数、通貨、%、日時、増減、否定、未確定、未知の漢字/英字単位のfixture |
| P0 | 日本語未確定変換中のBinding書き戻し、選択範囲の消失、終了時の未確定入力 | `MarkdownEditorField`：marked textはUIKit所有、確定時のみ反映、選択長保持、外部書き戻し中のdelegate防止。`EditableMarkdownDocument`, `InlineMarkdownEditor`：終了時に入力確定 | 自動入力と実機IMEは別。最終結果は [C](C_TESTS.md) |
| P0 | 親のSwiftUIメニューがUITextViewの選択メニューを奪う | `InlineMarkdownEditor`, `EditableMarkdownDocument`：編集中は親のカスタムメニューを抑制。編集終了後は従来のソース編集・表メニューを維持 | ネイティブ全文選択/ペーストのE2E。ドライバーのBackspace削除不具合も別途記録 |
| P0 | IME一時属性で分割された連続の太字/斜体を別Markdown構文へ変換 | `MarkdownEditingText`：意味上同じ書式の隣接runを結合してから変換 | UIKitのビルドとE2E。実変換候補の操作は未検証 |
| P0 | CIがjob envで無効なrunner contextを使用 | [CI](CI.md)：step envへ移動 | ローカルrunner単体検査。remote結果は別 |
| P1 | @記録にスキル/ツール/Notionを追加すると記録参照範囲が解除 | `AIPluginExecutionPolicy+Selection`, `AIPluginExecutionPolicy`, `MemoraModel+Agent`, `MemoraModel+AgentTools`, `MemoraModel+AutomaticRecordTools`：ツール許可とデータ許可を分離。記録限定時は全体の履歴・メモリを追加しない | 両エンジンのfactoryと本番readerを検査。選択外記録・タスク拒否 |
| P1 | 検索不一致でも直近200chunkを無条件取得 | `ProjectSearchIndex`, `ProjectContextBuilder`：文脈を引き継ぐ質問にだけfallback | 実FTS5、別project/削除/権限失効fixture。検索品質全体が完成したわけではない |
| P1 セキュリティ | MCP/OAuthのDNS検査後、URLSessionが接続先を再解決 | `MCPPinnedHTTP`, `WebSourceRequest`, `PinnedHTTPSConnection`：検査したnumeric IPへ接続、元hostのTLS検証。redirect/自動再送なし | 本番parser/transport/OAuth actorをoffline wire fixtureで検査。実サーバー・実機・ブラウザーは未検証。詳細 [G](G_MCP_STORAGE_FOLLOWUP.md) |
| P1 通信 | MCP返信の受け渡し後にsession IDを保存すると、SDKの次の通知に間に合わない | `MCPHTTPResponseState`：返信をyieldする前にsessionを同期的に公開、切断/キャンセル後のcallbackを失効 | 初回sendの復帰を保留したまま、次のnotificationがsession付きで送られるrace fixture |
| P1 保存 | 既存親フォルダと新規子ファイルでFoundationの`/private/var`正規化結果が異なり、正しい新規保存を拒否 | `ProjectSourceFiles.resolve`：既存親を先に正規化してから子パスを組み立てる。逸脱/子symlinkの拒否は維持 | 修正前full runnerでinvalidFileを再現、修正後は同じprivate/var環境の保存/SQLite/競合と別名親/新規leafのfixtureがPass |
| P2 診断 | 256イベント以降の保存/終了理由が診断画面から消える | `SummaryDiagnostics`：開始+末尾255件を保持し省略数を表示 | 608イベントでも最後の保存失敗・終了理由、モデル識別子の秘匿を維持 |
| P2 | 読みやすさ指針の上流更新 | `ReadabilityGuide`, `THIRD_PARTY`：yomiyasu 2.4.0に追従。担当/通知先の創作禁止、文脈限定の用語整理、スライド限定の読点 | 指示組み込み検査。実モデル文章のA/B評価未実施 |

## 維持した保護

- 本文の生成に失敗した場合に文字起こしへ戻る処理、要約/タスク/ジョブの原子的保存、保存前のrun ID・原文fingerprint・最新権限・workspace世代検証を維持。
- HTTP 408/504、502/503、URLSession切断/timeout、ユーザーキャンセル、background expirationを区別。無条件リトライは追加しない。明示的な出力上限の継続だけ既存の有限回数を維持。
- 実行直前のプラグイン/MCPのアカウント・設定・許可・コスト確認、変更ツールの承認、引用の型付きID、復元時の実行権限非復元を維持。
- 既存SQLite文書形式は変更しない。新しいジョブ日時はoptionalで旧データ互換。録音/写真のファイル参照、復旧draft、バックアップのtransaction/ファイル保持を維持。
- Bundle ID・署名・App Groups・CloudKit設定・ブランド・タブ構成・Liquid Glass適用箇所は変更していない。

## 未修正／未検証のリスク（次の安全な実装候補）

| 優先度 | 残課題 | 根拠と必要な次の検証 |
| --- | --- | --- |
| P0 | 実際のDeepSeek50秒失敗の確定 | 新診断のjob ID/終了理由との照合。有料APIを無断実行していないため、実経路での再検証は残る |
| P1 外部互換性 | IP固定MCP/OAuthの実サーバー検証 | クライアントの再解決経路は修正。現在はHTTP/1.1・identity encoding・単一の検査済みIPを使用。H2専用/圧縮専用・不足した証明書中間CAのオンライン取得・複数IPの自動failoverは未対応。実サービスE2Eと任意サーバーの運用保証は別途必要 |
| P1 配布 | 任意MCPサーバーの本番管理 | DNS rebinding自体はクライアントIP pinningで防げる設計だが、接続先審査・認可・監査・料金/上限をMemoraが一元保証する運用には、信頼されたバックエンドによる登録/制御を推奨する（設計判断）。個人BYOKの直接接続と管理サービスの保証を区別する。現状を本番安全性確認済みとは評価しない |
| P1 保存/性能 | 1件更新も配列文書全体をencode | `RecordStore.save` は直列queue上でencode/writeし、順序を保護するが全量負荷は残る。単一record保存へ移行するには実データ相当の計測、二重読み込み/移行マーカー/ロールバックを別途設計。今回データ形式を変えない |
| P1 検索 | fixtureの送信根拠の適合率が十分ではない | 11問のhit@1/Recall@3は良好でもunrelated-sent=0.500。現fixtureでこれを隠さず、否定例・曖昧語・複数根拠を増やしPrecisionも改善する必要あり |
| P1 図解 | 語の一致は意味全体の証明ではない | 誰に対応する数値か、未知の表現の否定/条件/因果は完全には判定できない。不確実な場合は生成を拒否し元要約へ戻す。数値正当性やモデル解釈の完全保証はしない |
| P1 実行環境 | 実機IME、OS中断、録音負荷、空き容量/保護状態の実OS、外部サービス | fixtureの成功と実環境の成功を区別する。コードとSQLite失敗は検査したが、デバイス/アカウントが必要な検査は未実施 |

外部費用や不可逆操作は実施していない。機能の削除、テストassertionの削除/skip、正常なセキュリティ制限の緩和は行っていない。
