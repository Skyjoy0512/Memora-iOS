# 共通AI処理改善（2026-11-15）

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

## 単位4: 現行Knowledgeの再利用境界・SoT容量

既存Ask AIとProjectEvidenceのSummaryKnowledge利用を確認。Meeting.reusableSummaryFactsを
共通の読み取り境界にし、現在のsummary版本/原文fingerprint/本文/抽出listの一致に加え、
各根拠の一意なUUID・引用・話者ID・件数・schema・重複を再確認する。原文にない/無根拠の
過去enrichmentを検索contextへ再昇格しない。状態labelと原文IDを保持し、Ask AIへ渡すときは
引用も含める。元の原文検索・ProjectSearchIndex・時間/権限再検証を維持する。
本人編集済みの抽出は既存reconciledUserEditsのレビュー扱いを維持し、自動memory登録しない。
人物の実名推測・同姓同名の自動統合や永続memoryへの自動書込は追加していない。

SoTのplan応答は最初のrequestではoutput予約でありinputではない。固定256KiBをinputにも
重ねて予約する判定を除去し、section生成時に実際の共有plan/promptサイズを別budgetで計測。
有料plan後の容量不足はexecutionLimitで終了し、自動でsingle-passを買い直さない。
共通planのspeakerIDsも引用元話者へ拘束し、発言者であるだけでownerと認める判定を除去。
通常採用gateは空のまま。mock成功で本番を有効化しない。

検証: adaptive-summary checks（実Meeting/history codec、原文/編集失効、不正引用/話者の
再利用除外）、summary-reading checks（SoT候補、並列順序、429、cache、parser）成功。
iOS Preview成功。意味的な引用と主張の含意や見落としは、この局所検証だけでは保証しない。

## 単位5: 限定評価ランナー

model_runner.pyに明示manifest、専用key、送信許可grant、request/token/USD/deadline、
独立した外部spend guard必須のopt-in実API実行経路とoffline preflightを実装。
推論込みoutput上限/価格不明、入力hash不一致、未レビューoption、再送、redirectを拒否。
通信は子processの絶対deadlineで停止し、途中課金は不明のまま保存する。
J-MeetEval197件/16分類・gold25件と既存公式/決定論的評価は変更しない。

このrunnerはraw API requestの測定用。ネイティブ要約pipelineの7方式を実行/計測するexporterは
未実装であり、Level 3完了とは報告しない。measurementKindはraw-provider-requestで、既存の
本番採用比較へ混入できない。source内の数値やgoldを生成結果の正解欄へ補完しない。
8単体testと既存evaluation suite成功、外部requestは0件。実API評価は実行していない。
外部prepaid/proxyが費用上限を実際に強制する設定は実施していない。詳細はtools/evaluation/README.md。

## Tokenizer調査

2026-11-15に公式資料を確認:
- https://api-docs.deepseek.com/quick_start/token_usage/
- https://developers.openai.com/api/docs/guides/token-counting
- https://platform.claude.com/docs/en/build-with-claude/token-counting

DeepSeekの文字比率は概算で、モデルにより異なる。公開offline tokenizerがこのカタログの
各exact model IDと同一であることは未検証。OpenAIもplain text tokenizerだけではmessage/tool
framing等を完全計測できないとする。Anthropicの計測APIは原文送信が必要。
今回その外部計測は行わず、未検証比率でcontextを拡張しない。アプリへのtokenizer資産の追加、
モデル別計測の本番接続、UTF8容量計画の置換は残存課題。安全なfallbackは維持する。

## ビルド警告の分類

iOS 27.2 SDK / iOS 26 deploymentのPreviewで11件を確認:

| 件数 | 発生箇所 | 原因・扱い |
| --- | --- | --- |
| 3 | PlaceNameResolver | CLGeocoder/reverseGeocodeLocation、MKMapItem.placemarkの非推奨。地名のfallback/API応答を変えるため今回変更しない |
| 2 | JournalMapSheet | MKPlacemark、MKMapItem(placemark:)の非推奨。MapKit移行時にMapsへの引渡しを確認する |
| 3 | JournalPlacePicker | placemarkの非推奨。位置の保存/Map検索回帰を伴う別単位で移行する |
| 2 | GmailAuthorizationSession/MCPOAuthBrowser | sceneに結び付かないfallback window初期化。認証UI/scene切替検証が必要で未変更 |
| 1 | appintentsmetadataprocessor | extensionのAppIntents.framework依存が無い抽出skip。本体buildを妨げず、警告抑制のための不要依存追加はしない |

bitrig test -listはProject.jsonにXcode test targetが無いためexit78。xcodebuildへ切り替えず、
既存のproduction Swiftを直接compileするhost test、実SQLite、e2eとPreviewを使う。

## 最終レビューの補修

- 新規cloud provider既定をDeepSeekに変更。保存済みprovider、登録済みmodel、旧OpenAIの
  明示model/keyは移行時に尊重する。端末内/自動というengine設定や実行中requestは変更しない。
  provider復元全caseとlegacy有無をhost testで検査。
- 再利用factの重複除去を根拠検証後に実施。不正な先行duplicateで正しい後続factを隠さない。
- modelがorigin=userを返してもappがgeneratedを割り当てる既存対応を確認し、回帰testを追加。
  重複したorigin実装は追加しない。
- raw runnerの不正応答shapeも、課金状態不明の失敗として保存し停止。runner単体testは8件。
- resident fixtureの新しいpriority/authorize契約を更新し、background指定もassert。
- 138 UIケースをinventory化。設定UI testは旧文言・旧配置ではなく、実際に対応providerを選び、
  詳細設定を展開して独立した詳しさ/処理設定/送信先/生成なしを検査する。生成/APIキー入力はしない。

P0の/tmpログはWorkspaceSSD/MemoraSummaryPerformanceValidationにも複製して保持した。


## 最終統合検証

`common-ai-quality-note-capacity`は全10群成功。source SHA256は
`22154d323174e7b4327363858479ad6033e687c69a0e67fa3665833e322e8803`で開始/終了/最終確認まで一致。
その前の`common-ai-quality-final`も全10群成功したが、その後にdefault/認可callback等を補修したため、
最終結果の正本はnote-capacity側とする。初回integratedの9成功/1失敗は上書きしない。

最終UI: 同一runで適応型要約166.50秒、原文保存失敗の復旧89.95秒、処理設定101.31秒の3件成功。
これらはUI操作全体の所要時間であり要約生成latencyではない。
全138件のうち3件成功/135件未実行。初回の旧文言、native BackButton、provider/詳細設定前提、
DisclosureGroupによる子ID継承の失敗を保存し、既存UIを変更せずfixtureとlocatorを補修した。
agent/model tokens=0、実API評価=0。最終UIもsource fingerprint不変。

認可の最終補修はCloudAIService.complete/answerとAIEngineService.answerに既存context closureを渡し、
待機後にcredentialだけでなくsource/workspace/snapshotを確認。実HTTP fixtureでqueued completionも
contextChanged/送信0件を確認した。公開serviceの追加呼出しや自動retryは無い。

詳細な18項目の結果は[REPORT.md](REPORT.md)、機械可読情報は[VALIDATION.json](VALIDATION.json)、
UI全件の実行状態と失敗を含む履歴は[UI_TEST_STATUS.json](UI_TEST_STATUS.json)。

## 中間notesの容量境界の補修

キャッシュ保存256KiBと最終統合への受理上限を分離した。検証用の有界decodeは4MiBまで、
選択modelのsourceCapacityを超えるnotesは受信直後に停止する。256KiB超でもmodelに収まる
正当なnotesはuncachedのまま保持し、本文の切詰めで速度を稼がない。cache hitもheader込みで
model容量を再確認する。大きいnotesを最終mergeへ渡すmock回帰、容量超過後の追加dispatch禁止を検査。
最初のfixtureは短いIDだけを仮定し失敗したため実UUID/短IDの両方に対応した。
先行note-boundsの品質/UI実行は容量guardを追加する前に中断し、その結果を最終成功と扱わない。
最終note-capacityの10群/UI3件はいずれも同一source指紋のまま終了した。

## 単位6: native host評価ランナー

fcd0e1ceでraw request単体に加え、本番MeetingSummarizer/planner/scheduler/cache/
CloudAIService/URLSession/SSE/parser/LocalStoreを直接使う開発用host runnerを追加した。
比較hookはMEMORA_SUMMARY_EVALUATION付きの専用compileだけに存在し、Project.jsonへは設定しない。
通常アプリのSoT採用ゲート、並列上限、選択モデル、詳細度、推論設定は変更しない。

7方式を同じimmutable source/model/preferencesで実行する。分割容量は既存容量を下げることだけが
可能。一括が収まらない/階層が一部分しかない場合は別方式へ読み替えず拒否。cache-warmの準備も
独立したphaseとして記録し、同じrequest/token/USD上限から消費する。modeの差で速度を稼がない。
capacity-single-passは現在の短縮IDと保守的なUTF8容量計画であり、tokenizer導入済みとは呼ばない。

資格情報を持たないSwift driverは全URLSessionをfail-closed URLProtocolで捕捉する。
専用評価keyと明示許可はPython brokerだけが持ち、生成された各requestについて再認可と共有予算予約を
実施してから独立子processへ送る。SSEは本文完了までbufferせず転送し、本番decoder/診断を使う。
429/期限/許可失効/上限は追加送信を停止し、リトライしない。通信中の取消は対応する子processを終了。
実行sourceとcompiled binaryをmanifestへbindし、compile前後/実行前後/各runのsource guardを維持。

P50/P95/最大と失敗率をcohort別に集計する。失敗の短い時間を成功latencyへ混ぜず、warmupも分離する。
未知の費用/意味品質/端末資源はnull。host-summary-documentは生成結果の実SQLite write/readbackであり、
iOSのrecord/task/history全transactionではない。broker IPCを含むhost時間をiOS実機値とは呼ばない。
automaticAdoptionは常にfalse。外部課金hard capの運用確認や実API評価は実施していない。

無料検証: 7単体test、7方式/8phase、分割SSE、cache hit、実SQLite、429/timeout/総予算超過/許可失効の
4経路が成功。全失敗経路でmock送信1回だけ、merge/repair/retry/完成summary保存なしを確認。
先行試行はhost用LLMSelection JSONに必須supportsToolCallingが無く起動失敗し中断した。
契約を補完し、対話backtraceを無効化、driverを専用環境へ隔離した後のv2〜v5が成功。
初回compileのAgentSessionBudget依存漏れとMeetingSummary非Codableへの誤った仮定も修正した。
後者は本番型を変更せず、開発用snapshot codecで解決した。原ログはnative-runner-v1〜v5.log。
今回の無料成功は実モデル品質・速度・費用の証明ではない。

## UI確認の拡張と旧fixtureの修正

native追加後の8件は初回6成功/2失敗。background-summaryは旧タイトル/ボタン/説明文を参照し、
draft-protectionはcomposer下書き破損時の旧global停止alertを期待していた。a16d3edd時点から
既に現行の「要約が途中で止まりました」/「もう一度要約する」とcomposer個別保護/復旧画面だった。
アプリのUIや保存基盤を変えずにtestだけを現行契約へ合わせ、単なる文言検査を
requiresUserRetry/attemptStartedAtの未実行検査、入力の無効化、復旧画面、再起動後の破損byte/本文保持へ置換する。
最初の修正後は下書き2件成功、backgroundの削除済み説明文がもう一つ残り再度失敗した。
失敗したrun/report/screenshotは削除せず、UI_TEST_STATUS.jsonに履歴を保持する。
各実行中はsourceを固定し、host品質群の実行中にlocatorを変更しない。

最終結果はUI最新8成功/0失敗/130未実行。native初回8件の6成功/2失敗、recovery-currentの
2成功/1失敗、background-finalの1成功を履歴に保存し、過去失敗を消していない。
生成ボタンを開いても実行開始時刻が付かず、cancel/restart後も原文・要約・待機jobを保持した。
本番ソースはfcd0e1ceから不変で、fixture変更はd37fd8f4。
10群はnative/recovery-currentの両runで10成功。最後の変更はbackgroundテストの説明文assertだけで、
host10群には影響しない。10群のf9b7f259と最後のUIのbba4938cは同一と偽らず、各runのguardを記録する。
以後はdocsだけを更新し、追加の実API/実機評価は実行していない。
