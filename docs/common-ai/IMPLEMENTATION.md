# 共通AI処理改善（2026-11-16）

基準HEAD: a16d3edd（依頼のe61f674eより新しい）。開始時mainはclean。

## 契約

既存Source Adapter/抽出 → MeetingSummaryInput/TranscriptSegment/SummarySourceIndex →
SummaryTokenBudget/SummaryInputPartition → MeetingSummarizer → SummaryKnowledge →
既存の本文・Ask AI・検索・人物/プロジェクトを使う。新しい要約エンジンやDBは追加しない。
入力形式固有の取得・OCR・STTは既存adapter側に残す。Knowledgeは原文の代替ではない。
録音中のクラウド分析・ライブSTTからの先行要約は今回の対象外。
保存済みSourceMediaChunkRevisionとライブ文字起こしは維持する。

## 単位1: 部分応答の受理ゲート

応答の完了はCloudSummaryResponse/stream終端検査、構造と根拠の受理は
SummaryPartArtifact.acceptance、キャッシュ保存はscope/authorize/leaseで別に判定する。
JSONの必須項目欠落、切断、誤型、空根拠、存在しないID、別partの引用、架空引用は
最終統合へ渡さずgenerationFailedとする。authorizeやcache scopeが無い場合も同じ。
分離できない自由記述notesの一部だけを残す修復は行わず、追加APIも呼ばない。
旧自由記述は従来どおり利用可能だがキャッシュ保存しない。

引用一致は文の意味的整合性や網羅性の証明ではない。話者・数値・否定・訂正・提案/決定の
意味的誤りは独立した評価を必要とする。根拠IDが有効なだけで意味検証済みと呼ばない。
保存・編集・完了タスクの既存確定処理は変更しない。

検証: run-summary-reading-checks.sh成功（実orchestration、mock API、既存parser）。
追加10ケースは不正partからmerge/修復requestが送信されないことを検証。
iOS bitrig preview成功、既存11警告。途中にAcceptance内Selfの型指定誤りでcompile失敗、
明示型へ修正後に両検証を再実行し成功。実モデル/実機の検証はしていない。
ログ: /tmp/memora-common-p0.log（失敗）、/tmp/memora-common-p0-r2.log（成功）。
Preview: 2026-11-15T15-48-47-94f9efce.log（Bitrig logs）。

## 単位2: 所有者・区間ごとの再利用

SummaryArtifactCacheのleaseに有界な所有者世代を追加。原文の編集時はその所有者の旧leaseを
拒否するが、既存payloadを残す。削除・privacy・メタデータ・資料抽出変更は対象所有者だけを
失効/消去する。他レコードのcacheとworkerを一律失効させない。account/workspace/restoreの
全体失効は維持。所有者tombstoneは1024を超えると全体失効へ安全に戻す。

part identity v2は該当区間の原文・話者・時刻・IDを含み、全体原文fingerprintへの過剰な依存を
除去。prompt、順番/分割数、全体header/話者legend、scope、credential、provider/model/endpoint、
抽出観点、推論modeは引き続き照合する。区間境界やS番号が変わる場合は保守的にmissする。
後半の訂正は毎回全区間を再統合するため、前半cacheを独立した最新決定とは扱わない。

既存LocalStoreにconnection changes + SQLite data_versionの変更tokenを追加し、最大4MiB/32件の
検証済みcacheだけをactor内に保持。hitの度の全量SQLite読取/JSON decode/checksum再計算を抑制。
他connectionの変更、直接書込、TTL、破損、restartを再検証する。書込直後や読取中に外部更新が
あった場合はRAMを採用しない。上限、TTL、backup除外は変更しない。

検証: planning suite（実SQLite、他所有者保持、旧worker書込拒否、削除、破損、TTL/LRU）、
reading suite（mock request数5→1、1区間のみ改版時は2、毎回final merge）成功。
途中にLease型移行のcompile失敗、並行編集中のcompile検知失敗があり、安定sourceで再実行成功。
ログはWorkspaceSSD/MemoraSummaryPerformanceValidation/common-ai-cache-*。
Single-flightは検討したが、共有taskのsubscriber単位キャンセル/再認可契約が未整備のため未導入。
cache容量の増量や新DBはない。実モデル性能・端末RAM/電池の改善量は未計測。

## 単位3: 共有API admission

既存SummaryRequestAdmissionを全CloudTurnStreamingとCloudAIServiceの非stream経路、
CloudAgentSessionの非stream経路へ共有。endpoint + 認証headerのhashで分離し、modelを越えて
同じ資格情報の制限を共有。connection poolや本文/秘密値は共有しない。permitは本文受信完了まで
保持し、tool実行前に解放する。tool実行中にslotを保持する親子deadlockを避ける。

3段階の優先順位と最大3回の追越しを導入し、低優先度の永久待機を防止。常駐agentはbackground。
既存16待機/64scope/120秒/キャンセル/429 fail-stop/Retry-Afterを維持。
RPM/TPMは明示されたaccount契約だけを使用し、未知値はnil。TPMは本文byte上界+出力予約+
framingの保守的な送信予約で、実usageや費用とは呼ばない。枠不足は送信前に拒否し自動再送しない。

能力表の明示maximumConcurrentRequestsは1〜4に有界化。未知BYOKは従来の1/2を維持。
端末の低電力/serious thermalで送信時にも1へ下げる。高並列のaccount契約は現在カタログに
登録しておらず、単に最大2を全providerで解除したものではない。メモリ余裕を入力できるpolicyは
あるが、実端末の空きRAMを使う接続やlatencyに基づく自動昇格は未実装。

送信待ち後にcredentialと既存agent/project/record/research/resident認可closureを再確認。
既存tool承認は引き続き実行時にも再確認する。要約以外の任意クラウド処理の全ライフサイクルを
一つの新serviceへ移行したとは扱わない。未確認価格・usageは従来どおり不明。

検証: planning（1/2/3/4、FIFO、優先度aging、RPM/TPM予約、scope、cancel、429、期限）成功。
cloud-session（本番HTTP/SSE/JSON/parser/agent/SQLite、要約slot待機中agentの送信前認可取消、
両stream方式の送信0件）成功。外部network/API/keyは使わない。iOS Preview成功、11既存警告。
途中に共有429状態を独立HTTP status fixture間で持ち越す失敗があり、fixtureに独立admissionを注入。
別のassertConsumed失敗は再現しなかったためログを保持し、期待値は緩めず診断を詳細化。
新testのclosure型推論compile失敗は明示Task型/分岐へ修正。
ログ: common-ai-admission-planning.log / common-ai-cloud-session*.log（WorkspaceSSDの検証directory）。
