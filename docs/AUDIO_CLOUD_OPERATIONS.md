# Audio Intelligence — クラウド・原価・提供条件

2026-11-02に公式ページを確認。未提供の比較案。既存の価格・権利・販売状態は変更しない。
再計算は `python3 tools/checks/audio-cost-scenarios.py`（全組合せJSON）、
`--markdown`（[主要表](AUDIO_COST_SCENARIOS.md)）、`--check`（算術検査）。
既存の `pricing-scenarios.py` と `PRICING.md` の旧案も比較対象として保持する。

## STT比較

| 候補 | USD/時 | 仕様・採否 |
| --- | ---: | --- |
| [Cloudflare Whisper](https://developers.cloudflare.com/workers-ai/models/whisper/) | 0.02718 | モデルページ$0.000453/分。料金一覧の旧表示$0.0005/分との差があり、接続前に見積り再確認 |
| [Cloudflare Whisper large v3 Turbo](https://developers.cloudflare.com/workers-ai/models/whisper-large-v3-turbo/) | 0.03078 | $0.000513/分、language/VAD/segmentsあり。日本語正解評価後の第一候補 |
| [Groq Whisper Turbo](https://console.groq.com/docs/model/whisper-large-v3-turbo) | 0.04 | 多言語。10秒の最低課金、free/devのfile制限を区別 |
| [Groq Whisper large v3](https://console.groq.com/docs/model/whisper-large-v3) | 0.111 | 多言語。Turboとの日本語CER比較が必要 |
| [OpenAI Whisper](https://openai.com/api/pricing/) | 0.36 | 既存BYOK。25MB/要求、verbose_json区間時刻、話者分離なし |
| [OpenAI mini transcribe](https://developers.openai.com/api/docs/pricing) | 推定0.18 | 表示目安$0.003/分。token課金で、分単価の固定保証ではない。時刻/形式がWhisperと異なる |
| [Deepgram Nova-3 multilingual](https://deepgram.com/pricing) | 保守値0.552 | 取得した料金表$0.0092/分。検索indexには旧pre-recorded$0.0052/分も残る。販売用計量に旧値を固定しない |

Deepgramの料金表は秒単位、複数channelは合算時間の課金と記載。
話者分離は追加$0.0020/分、Keytermは追加$0.0013/分。
アプリは追加課金の話者分離を自動要求しない。返ったspeaker情報のdecoderは保持する。
既存の用語集を送る場合はKeytermを使うので、$0.0105/分（$0.63/時）も別scenarioに含める。
用語強調/話者分離込みの価格を、base STT料金と混ぜて低く見積もらない。
Nova-3の日本語・keytermは[対応言語](https://developers.deepgram.com/docs/models-languages-overview)と
[keyterm](https://developers.deepgram.com/docs/keyterm)に掲載。アプリはmono/単一レスポンスの
utterance時刻と匿名clusterを保存し、名前や確信度を創作しない。
Groqの[API仕様](https://console.groq.com/docs/speech-to-text)では小さい発話を大量のrequestへ
分けると最低課金が支配する。VAD後も適度にまとめ、余白と時刻mappingを保持する。

無料credit、cache hit、off-peak、販促価格は利益の前提にしない。どのcloudも日本語の
精度・日本からの実遅延は未測定。安さだけで本番採用していない。
FluidAudioの追加ASR・RE-USE・GPUは品質/ライセンス/iPhone容量・RTFの比較待ち。

## VAD・720時間の計算境界

原本720h = 43,200分。CF Turboは全量$22.1616（FX160: 3,545.86円、FX200: 4,432.32円）。
Groq Turboは$28.80（FX200: 5,760円）。いずれもSTTだけで、要約等を含まない。
VAD後25%の音声を**実際に端末から送った場合**のCF Turboは$5.5404（FX200:1,108.08円）。
75%/3,324.24円の差は仮定上のSTT減少で、実現した節約ではない。
server内の`vad_filter`だけをONにして、元音声uploadの長さまで25%課金になると考えない。
サービス側の最小秒数、padding、retry、provider実測のusageを確定時に使用する。
今回切除を本番有効にしていないため、実績としてのVAD節約は**未測定**。
処理時間はlocal VAD/codec/upload/queue/STTの合計であり、発話比率と同じ倍率で短くなる保証はない。

全量720hを1時間ごとに要約する想定では、入力25,000・出力3,000token/時 ×720、
[DeepSeek peak](https://api-docs.deepseek.com/quick_start/pricing/)入力$0.30/百万・出力$1.20/百万なら
約$7.992（FX200:1,598.40円）。これは仮定の追加原価で、Ask AI・agent・階層統合は別。
全文を質問のたびに送り直さず、既存の許可付き検索から関連区間を渡す。日別の永続要約cacheと
複数日の階層は今後追加し、今回の1記録内の階層統合と区別する。

## 推奨構成と選択肢

まず端末内+BYOKで提供を続ける。Memora提供cloudを導入するなら、API/queue/台帳/一時保存を
Cloudflareへ寄せる案を第一候補とする。リージョンは日本固定にせず、日本からのp50/p95と
data locationを測って選ぶ。Workersのedgeから、D1の配置先や海外AIまでの往復は残る。

| 項目 | 公式費用と制約 | 判断 |
| --- | --- | --- |
| [Workers](https://developers.cloudflare.com/workers/platform/pricing/) | Paid最低$5/月、10M request/30M CPU-ms込み、超過$0.30/M request・$0.02/M CPU-ms | GPU/STTをWorker CPUで回さず、API制御に限定。CPU上限も設定 |
| [Queues](https://developers.cloudflare.com/queues/platform/pricing/) | Paid1M ops/月込み、超過$0.40/M、通常write/read/deleteの3操作 | 音声bytesを載せずjob参照のみ。retry/再配達にも予算予約 |
| [D1](https://developers.cloudflare.com/d1/platform/pricing/) | Paid25B read/50M write/5GB込み、超過read$0.001/M・write$1/M・storage$0.75/GB月 | 最新の専用ページを採用。Workersページの$0.20/GB表示との差は接続前確認。台帳は1個から |
| [R2 Standard](https://developers.cloudflare.com/r2/pricing/) | $0.015/GB月、A$4.50/M・B$0.36/M、Internet転送・取り出し料金なし | 15分chunkの一時置場。IAは取り出し/最低保持条件があるので使わない |
| [Backblaze B2](https://www.backblaze.com/cloud-storage/pricing) | $6.95/TB月、API無料、storage3倍までegress無料 | 保管は安いが短期の音声再取得で無料転送枠を超え得る。複数サービス運用になる |
| [IDrive e2](https://www.idrive.com/s3-storage-e2/pricing) | $6/TB月、1TB未満も$6最低、API無料、3倍超egress$0.01/GB。初年度値引きは除外 | 小さな一時置場には最低料金が不利 |
| [Supabase](https://supabase.com/pricing) | Pro $25/月から。8GB DB、250GB転送等、Freeは非稼働1週でpause | 認証・teamに有用だがD1より固定費が高い。今回は接続/契約しない |
| SQLite + 既存ローカルファイル | cloudの録音保存費0 | 個人用の標準。端末容量/backupは利用者が管理 |
| CloudKit private/shared | 個人privateは利用者のiCloud容量。service側publicと同じ予算に混ぜない | 現行sharingはread-only snapshot。音声同期・team DB/権限の代替として新規接続しない |

Workers Paidを使う案の基礎固定費は$5/月（800～1,000円/FX160～200）で、
上限まで込みという意味ではない。Apple Developer会費・ドメイン・人件費等は別。
1/10/100/1,000/10,000人の配賦と並列8のwave数は[生成表](AUDIO_COST_SCENARIOS.md)に記載。
同時利用で費用上限を増やさず、1人1実行・全体8実行から開始する案。長い待ち時間は
実測後にSLOを定める。1万人同時なら少なくとも1,250waveで、即時完了とは言えない。
cloud枠があっても全体障害/停止が起こり得る条件は販売前に定義する必要がある。

固定費の無料運用は可能な範囲でのみ使う。Workers AIの無料10k neurons/日は共有枠で、
利用者ごとの無料枠としない。予算に達したら外部実行を止め、無断で高いproviderへfallbackしない。

## 保存・削除と権限

個人録音の永続cloud保存は標準にしない。端末原本は保持。個人backupとteam storageの
契約・認証・権限・meterを分離する。teamは未接続のままであり、local plan変更で開放しない。
一時audio案は15分chunk/最大25MB、upload URLは本人+jobへ限定して5分で失効。
完了/失敗/取消時に即時削除を試み、1時間で再試行job、24時間でアクセスを必ず拒否する。
R2 lifecycleは1日を防護として設定するが、[物理削除は期限後通常24時間以内で遅れ得る](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)。
したがって「24時間で必ず物理削除」と表示しない。削除workerと実S3/API検査は未実装。
この設計の運用検証完了前にaudio upload endpointを公開しない。

[Cloudflareデータ取扱い](https://developers.cloudflare.com/workers-ai/platform/data-usage/)は標準推論で
処理後保持なし・training不使用とするが、stateful機能・法的例外・運用metadataを区別する。
[Groq](https://console.groq.com/docs/your-data)はZDR設定を確認し、通常の障害/濫用調査の
最大30日保持とbatch保持を別に扱う。Deepgram/OpenAIも本番契約・account設定ごとの
保持・学習opt-outを確認するまで「どこにも残らない」と説明しない。
fallbackは相手先・同意・価格を再検査。録音/文字起こし/鍵を診断logへ載せない。

## 課金基盤の実装範囲

`backend/audio-intelligence/ledger.sql` と `ledger.mjs` は非公開の台帳コア。
整数micro-USDで、同じstatementのtrigger内で本人と運営全体を予約する。
STT秒・AI原価枠・request数・並列枠を独立制限。未知/期限切れ価格、契約失効、
同時reserveの超過を拒否する。許可/契約/priceは実行claim時にも再確認する。
送信前release、実績settle、usage不明時の全額保持、immutable価格revisionと追記eventを持つ。
claim済みjobを自動再送しない。timeoutやworker停止を無料として扱わない。

**まだないもの**: 公開API、server認証、App Store署名/通知検証、account発行、
原音声のserver側duration検証、provider実行・実usage、request hashのserver正規化、
privacy失効連携、R2削除worker、レート/IP/端末濫用対策、価格監視、返金/失効のE2E。
SQLテストは実SQLiteであり、D1本番・複数regionの実行検証ではない。
端末のAPI key/plan/credit値をこの台帳へ信頼して取り込む経路は作っていない。
`MemoraIntelligence`の未接続表示は維持し、課金開始/本番配備/外部契約は行わない。

## 料金案の判断

現行の未提供案は480/1,480/2,980/3,480円、credit300/800/1,500/1,500、cloud STT0。
生成表では全枠使用・15/30%手数料・税10%・FX160/200・値上げ1.5倍・retry1.25倍・
予備10%・年額10/11/12か月価格・全人数を計算する。収入は価格÷1.1×(1-手数料)。
予備10%は返金・濫用の仮定であり、返金率の無制限な悪化を保証しない。
DB/API/queue/監視は予算仮定。実costと監視counterがこの枠に入るまで販売判定しない。

同価格でcloudを含む候補は全て別案。旧creditを減らす案をアプリへ勝手に適用しない。
同条件100人のunlimited/team候補は利益率8.7%/2.3%で余裕が足りないので**推奨しない**。
初期の推奨は端末内/BYOK継続。将来cloud専用案なら2,480円/20h/300credit、
7,980円/100h/700creditを比較候補とし、日本語品質・全費用・認証/購入検証を満たしてから再判断。
年額値引きは当初なし（12か月価格）を候補にする。安い旧年額が安全とは言えない。

720h録音してもcloudは購入枠まで。残りは端末内・BYOK・後で再試行。
追加時間packも別の予約上限を持ち、利益を検証してから販売する。
運営全体の上限は、受領済み純収入から固定費・返金準備・目標利益を差し引いた値以下に
serverが設定する。収入不足時にcloud販売・新規契約を始めない。
固定費を1人に配賦すると低価格tierは赤字なので、「全員が使い切っても必ず黒字」とはまだ言えない。
