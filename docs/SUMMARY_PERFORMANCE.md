# 要約性能の測定

利用者報告: 文字起こし済み1時間相当の要約が120秒超。これは現環境で再現計測した値ではない。目標60秒、次段階30秒、録音終了後の追加待ち10〜20秒は未達成・未検証。

要約以外のSTT、話者分析、取り込みから保存までを混同しない。既存 `AudioProcessingDiagnostics` のsummary / recognition / persistence等のspanと、`SummaryDiagnostics`のrequest別タイムラインを関連付ける。本文・キー・エンドポイント・ユーザー原文は診断に記録しない。

集計ライブラリ `tools/evaluation/quality_metrics.py` はP50/P95（nearest rank）/最大、既知サンプル数、不明サンプル数を返す。未提供usage、料金、端末CPU・電池を0に置換しない。TTFT、first reasoning、本文生成時間は別列。初回推論イベントは「推論処理全体の実時間」を意味しない。

旧/新は同一原文・指示・モデル・推論・出力予算・データ版・プロンプト版で比較する。cold/warm、1/2/3/4並列は別cohortとして複数回測定。API混雑とrun差を報告し、仮想時計のscheduler試験を実APIの秒数として扱わない。

実API・実機を使わずに証明できるのは、入力のbyte削減、処理計画、キャンセル、正しい順序、ローカル実装の所要時間まで。API token削減率・コスト低下・60秒以内の達成は別途計測が必要。

## Phase 2: 入力IDと計測

`SummarySourceIndex` は不変の入力配列順にS1…を割り当て、元のTranscriptSegment（UUID、開始/終了、話者ID・確度、原文）を参照する。話者の対応はJSONで一度示す。原文の本文・改行・空白・記号はそのまま。対応表の費用を含めて小さくなる場合だけ短縮表現を採用する。元の文字起こし・保存済み本文は書き換えない。曖昧な重複UUID・未知ID・原文にない引用は根拠に昇格しない。

モデル出力の構造化参照だけを元UUIDへ戻す。本文のS番号を文字列置換する処理はない。短縮表現を送信しなかった場合には、モデルが返したS番号を出典として認めない。ProjectSourceのページ情報は既存の「ページn」話者ラベルとsourceContextに保持される（独立したpage索引への拡張は次段階）。

1,000発言の合成fixtureでは、従来入力199,999 bytesに対し、話者対応表込み151,139 bytes（24.43%減）。モデルのtokenizerを使った値ではなく、APIの速度・費用の削減率でもない。全文・話者・順序・IDの往復を実コードで検証した。

診断にcachedInputTokens/cacheWriteTokensとsource bytesを追加。`SummaryDiagnostics.metrics` / `metricsJSON` がrequestごとにHTTPヘッダー到着、first reasoning、TTFT、reasoning→本文の観測間隔、本文生成、応答完了の時間を提供する。parse/saveは別span。最初の推論から本文までの間隔は実際の内部推論の総時間とは呼ばない。ネットワークだけの時間やtokenizerが未提供のため、生成token/秒を推測して出さない。Anthropicのinput_tokensはcache read/writeを除く値であり、異なるproviderのcounterを無条件で合算しない。

1チャンク応答のfirst/last token時刻が逆になる既存の計測問題を修正。タイムライン上限で欠落した場合は `timelineIncomplete=true`。nullの使用量はJSONでは省略されるが、0として補完しない。


## 通信再利用

`CloudHTTPTransport` の寿命は1つの要約ジョブ。part/merge/final/continuationを同じURLSessionで送受信し、完了・失敗・キャンセル後に閉じる。認証hashはメモリ内だけでbindし、endpoint/auth変更やCookie指定は送信前に拒否。設定はコピーし、cookie/credential/cacheの共有を無効にする。redirectで原文の送信先を変えない。

同一sessionで3応答（長さ継続2応答+次区間1応答）、拒否した変更で追加送信0、caller設定を変更しないことをURLProtocolで確認。実MeetingSummarizerの全part/最終生成が同じtransportを渡すことも確認。診断のsessionReuseは論理sessionの再利用であり、実TCP connection再利用やTLS短縮時間の測定ではない。

SSEのバイトループとJSON蓄積は `@concurrent` でMainActor外へ移動した。UI通知だけを既存間隔でMainActorへawaitし、順序とbackpressureを維持。hostのproduction readerでoff-main実行とMainActor callbackを検証した。これは実機のUIフレーム時間やAPI速度の改善率の測定ではない。詳細は `summary-performance/TRANSPORT_DESIGN.md`。
