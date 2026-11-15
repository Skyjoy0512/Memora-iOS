# 要約ジョブ共通の送信制御（2026-11-15 追加）

基準 `a715fdd2`。既存SummaryPartSchedulerのジョブ内上限に加え、同じAPI枠を使う**要約ジョブ間**を制御する。UI、モデル、推論、原文、出力予算、テンプレート、保存スキーマは変更しない。実モデル評価は利用者指定で実行しない。

## 実装

`SummaryRequestAdmission` actorを既存CloudHTTPTransportとCloudTurnStreamingへ接続した。MeetingSummarizerの共通transportと、CloudAIService.completeStreamingの単独経路の両方が利用する。Ask AIのagent turnや非stream API全体へ新しい待機方針を広げていない。

1. endpointと実際の認証headerからSHA256のscopeを生成する。raw key/URL/原文はキューへ保存しない。
2. 同じscopeの全要約jobで上限を共有する。既存能力/低電力/thermal方針が返す1または2を守り、unknownや制限の強い先行requestをFIFOで追い越さない。
3. jobごとのURLSession/credential bindingは従来どおり独立。接続や本文・cacheを別job/ユーザーへ共有しない。
4. 枠取得後、送信直前にauthorizeとTask cancellationを再確認する。HTTPヘッダーだけでは枠を返さず、SSE/JSON本文と終端検証まで保持する。全失敗経路でも枠を返す。
5. 429を受信すると同scopeの未送信キューをrateLimitedで終了する。Retry-Afterの期間内の新たな試行もローカルで終了する。送信済みの別jobを再送しない。
6. cooldown後は新しく明示的に開始された処理を受理する。429受信から5分の間は同scopeを1並列に抑え、期間後は元の上限へ戻す。cooldown終了時に自動のAPI呼出しを発行しない。

制御範囲は同一アプリプロセス内であり、他端末/他アプリのAPI利用量や再起動を越えたquotaは分からない。

64 scope・合計16待機・待機120秒まで。待機中のrequest本文を保持するTaskが増え続けないよう、待機数を制限する。超過時はexecutionLimitで停止し、未完了データを完成として保存しない。待機timerもこの上限内で、許可/キャンセル/429時に破棄する。未完了workerのキャンセルは既存モデルの失効処理を維持する。

## Retry-After

[HTTP Semantics RFC 9110 §10.2.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3)に基づき、非負整数の秒数とHTTP日時（IMF-fixdateと旧2形式）を受理する。日時は受信時のwall clockから相対時間へ変換し、保持する締切はContinuousClockを用いる。

headerの省略/破損時は**アプリの保守的な方針**として60秒とし、providerのRPM/TPMを推測した値とは扱わない。1年を超す値・数値overflowは短い値へ切り詰めず、そのscopeをプロセス再起動まで停止する。scope数の上限に達しても有効なcooldownを追い出して送信を早めない。これは極端なheaderに対するfail-closed処理であり、外部への再問い合わせや課金探索はしない。

## 無料検証

`SummaryRequestAdmissionChecks` はproduction actorに対し、ジョブ間上限、厳しい先行上限、独立scope、FIFO、待機中/開始前キャンセル、429時キュー停止、120秒Retry-After、回復中の1並列、元の上限への復帰、日時3形式、巨大header、64 scope/16待機上限、待機期限を検証する。時間経過の大半は仮想時計、期限テストは短いhost待機であり、モデル速度ではない。

`CloudSummaryAdmissionChecks` は実CloudAIService→CloudTurnStreaming→URLSessionのoffline URLProtocolを使う。

| ケース | 実際に確認する送信数 |
|---|---:|
| キュー待機後の許可取り消し | 0 |
| キュー待機中のキャンセル | 0 |
| 先行jobがヘッダー受信後に本文待機、別jobが待つ | 本文再開前は1、完了後に次の1 |
| 429と、同scopeへの直後の再実行 | 合計1（追加送信0） |
| 仮想121秒後の明示的実行 | 新しく1、完了後active/waitingとも0 |

独立したHTTP失敗fixtureには独立admission actorを注入し、前の429が別ケースへ残る順序依存を避ける。共有状態の挙動そのものは上記の複数jobの試験で検証する。既存の失敗判定・選択model/endpoint・tool/JSON/SSE検証は維持する。

```sh
# scratchと結果は開発用SSD等、repo外を指定する
TMPDIR=/external/scratch/ SWIFT_BACKTRACE=enable=no bash tools/checks/run-summary-planning-checks.sh
TMPDIR=/external/scratch/ SWIFT_BACKTRACE=enable=no bash tools/checks/run-cloud-session-checks.sh
TMPDIR=/external/scratch/ SWIFT_BACKTRACE=enable=no bash tools/checks/run-summary-reading-checks.sh
python3 tools/checks/run-quality-checks.py --output-dir /external/new-admission-quality
bitrig preview -platform iOS
```

## 残りと採用範囲

これは並列数とproviderの429 feedbackによる制御であり、未確認のRPM/TPMを実装済みとしない。モデル別quota取得、token bucket、API混雑下の実throughput・費用・P50/P95、実機の電池/発熱は未検証。API request数を増やす自動retry、別model fallback、思考量変更は追加しない。

SoTの採用gateは閉鎖を維持する。録音中のクラウド先行分析、音声export/認識の新しい並行処理、実費上限付き評価runnerは依然未実装。音声は単一stage.audioURLを利用し、認識中のファイルを次のexportで上書きできない。二重bufferの容量予約・取消/cleanup・確定segment/話者・checkpoint整合と、録音drop/発熱の検証が必要であり、この単位では切り替えない。

ログの保存先は `/Volumes/WorkspaceSSD/Development/Agents/MemoraSummaryPerformanceValidation`。admission-planning / admission-cloud-final / admission-reading-checks / quality-admission-2026-11-15、iOS previewはadmission-delivery-previewを参照。最終結果は以下に追記する。実API latency・token・料金・生成品質の新しい実測値はない。

## 最終検証結果

コードを固定した実行で9群成功、next-generation群は音声再開fixtureの失敗後に、同じ判定条件で全体を再実行して成功した。`quality-admission-final-2026-11-15/summary.json`の失敗を上書きせず、`admission-nextgen-final.log`の成功を別の結果として保持する。音声単独試験も成功したが、最初の失敗原因は未確定。音声testには今回の送信制御がリンクされていない。再発時に理由を表示するdiagnosticだけを補い、期待値の緩和・アプリの自動retryを追加していない。失敗後に終了しなかったhost checkは停止した（そのrunのexit137）。

これ以前の実行では修正とSwift compileが重なりinput modifiedで失敗したため停止し、コード固定後に上記の全群を実行した。いずれの途中結果も成功へ書換えていない。

iOS最終build `2026-11-15T09-47-46-6ffe7001.log`、Bitrig preview `2026-11-15T09-50-05-69fda42b.log` は成功（既存11警告）。E2E run `01a1dcae-c9e3-7da7-8ed8-1544fa4d9dc9` は2選択・2成功、再起動後の初回完了状態と、狭幅/拡大文字/dark/表/チェックリスト/長文/Ask AI/本文不変を確認。modelTokens=0、maxModelCallsInStep=0。`.e2e/summary-admission/report.json`に保持。全138 UIテストを実行した意味ではなく、実機/VoiceOver/実サービス認証は未検証。

[機械可読な検証要約](admission-results-2026-11-15.json)は元の集計失敗と独立した再実行成功を両方保持する。実APIの速度・費用・要約品質は未検証、60/30秒目標の達成報告ではない。
