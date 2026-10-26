# AI待機表示・要約送信・録音リソースの改善

検証日: 2026-10-26。開始時に `git fetch github main` と fast-forward確認を実行し、GitHub mainとローカルはともに `4dbc5fa`。実装は `e8cdb51` と後続の計測・検証コミット。

## 1. 実Simulatorの変更前後

いずれも実際にアプリを起動したスクリーンショット。待機表示の比較は、同じ iPhone 18 Pro Max Simulator、同じ既存の「Ask AIの経過」表示fixtureを使用した。外部モデルを動かした画面ではなく、実際の `ThinkingTraceView` と `ConversationStatusLine` に架空の状態を渡す診断画面。

| 表示 | 変更前 | 変更後 |
| --- | --- | --- |
| 待機・Light | [実画面](qa/waiting-energy/before-waiting-light.png) | [実画面](qa/waiting-energy/after-waiting-light.png) |
| 待機・Dark | [実画面](qa/waiting-energy/before-waiting-dark.png) | [実画面](qa/waiting-energy/after-waiting-dark.png) |
| クラウド要約 | [Toggleあり・生成不可](qa/waiting-energy/before-summary-light.png) | [送信先表示・生成可能](qa/waiting-energy/after-summary-cloud.png) |
| 端末内要約 | — | [外部送信の説明なし](qa/waiting-energy/after-summary-on-device.png) |
| 録音 | — | [省電力・一時停止後に再開](qa/waiting-energy/recording-low-power.png) |
| Reduce Motion | — | [Simulatorのシステム設定を有効にした状態](qa/waiting-energy/reduce-motion-system.png) |

変更前の待機画面には、作業テキスト左側のゲージと経過秒、承認待ち左側のゲージがある。変更後は短い状態テキストだけ。以前のBitrig Debugビルドを保存して比較し、開始時のソースでも同じ旧ゲージ実装を確認した。主実行ファイルのUUIDだけではDebugビルドの同一性を証明できないため、Instruments採取では `.debug.dylib` も照合している。

## 2. 削除した装飾と維持した機能

- 主待機表示から `ThinkingGauge` と経過秒を除去。Ask AIの処理中mesh、コンポーザーの処理中pulse、ツール履歴の回転spinnerも除去した。
- `ShimmerText` を共用。本文待ちにだけ表示し、本文受信開始後は待機行を撤去。承認・質問待ちは静的な「確認を待っています」。完了・失敗・キャンセルでは待機行が存在しない。
- ShimmerのTimelineは、表示中・前景・Reduce Motion OFFの場合にだけ生成する。repeatForeverで残るアニメーションは作らない。
- `ThinkingTraceView`、単発の `AIQuestionView`、プロジェクトチャット、処理概要を調整した。プロジェクトのトークン受信判定は小さなleafに分離した。
- 状態のアクセシビリティラベルと状態変更時のAnnouncementを追加。SimulatorのReduce Motion設定でも静的な枝になることを確認し、設定は元に戻した。VoiceOverの実機での聞こえ方は未検証。
- 停止ボタン、Agent承認・質問、ツール履歴、エラー、出典、詳細表示は維持。経過時間は展開したツール履歴の中でだけ更新する。
- ブランドデータ、サイドメニューの通常ロゴ、色・Typography、Liquid Glass、カレンダー、ワークスペース順序は維持。`ThinkingOrbView` 自体は削除していない（現在の呼出しは見つからなかった）。

## 3. 要約の今回限りの送信

`SummaryGenerationSheet` のチェックボックスを撤去。生成ボタン付近に、選択したプロバイダーと実際の接続先host、「文字起こしを送信して生成します」を表示する。タイトル・日時・用語集・生成指示も送ることを併記する。端末内エンジンではこれらの外部送信表示を出さない。

生成ボタンは描画した同じ `configuration` を使い、`SummarySubmissionIntent` を作る。この非Codableのメモリ上の指示は、記録ID、原文等のfingerprint、workspace generation、engine、LLMSelection（接続先を含む）、ジョブIDに結び付き、一度だけ消費できる。同じ指示の再利用、異なる送信先・原文・workspaceへの転用は拒否する。

記録の継続的な許可は変更しない。未判定の記録は、この明示的な指示で今回だけ要約できる。分類済みでクラウド利用がOFFの記録や明示的に外部許可を取り消した記録は拒否し、既存のプライバシー設定から確認する。機密・要配慮区分を一般テンプレートへの変更で解除しない。今回の指示をAgent、Webhook、自動要約へ渡す経路はない。

実行中の各送信境界・進捗・結果適用で、記録、プライバシー、workspace、モデル設定revisionを検査する。fingerprintには、過去の要約形式や用途に由来する実効プライバシーも含める。後続の送信でも今回限りの専用ポリシーを使い、汎用のexplicitCloudConsentによる分類の迂回は行わない。モデル設定を変更して元に戻す場合もrevisionが変わる。原文や要約の変更を古い結果で上書きしない。Webhookと常駐Agentには従来の別の許可判定が必要。

`PendingSummaryJob.cloudDisclosureConfirmed` は旧データ互換用に保持するが、復元されたtrueの値で自動送信はしない。試行開始とrequiresUserRetryは送信より前に永続化し、プロバイダー側で課金済みの可能性がある試行を再生しない。中断後は新しい生成操作が必要。

追加したプライバシー属性はoptional。SQLiteのテーブル形式、音声参照、バックアップ形式、要約履歴は変更していない。新旧のcodec、実SQLiteへの原文・履歴・ジョブの原子的保存と再読込は既存/拡張テストで確認した。

## 4. 録音・認識のボトルネックと実装

| 調査で確認した点 | 今回の対応 |
| --- | --- |
| AAC保存とライブ用AVAudioEngine/SpeechAnalyzerが並行し、ライブ結果は保存原文に使われない | 通常/省電力を設定と録音画面で選択可能にした。省電力ではライブ認識・音量装飾のみ休止。AACの44.1kHz・mono・highは維持 |
| 低電力モードやserious/criticalの熱状態でもライブ認識が動く | 省電力動作へ切り替え、録音画面と設定説明に明記。OS通知で追従し、録音本体は停止しない |
| 非表示時にもメーターTaskが約345msごとに起床 | 非表示・背景・一時停止・省電力ではメーターTask自体をキャンセルし、AVAudioRecorderのmeteringも無効化 |
| 表示時は45ms sleepが2回あり、コメントの約22Hzとは異なりソース上の予定周期は約11.1Hz（実機起床数の実測ではない） | 100msの1回待機、10Hzに明確化。小さな変化ではObservation値を代入しない |
| 録音の秒数Taskが背景・一時停止中も起床 | 背景・一時停止中は停止。復帰時にAVAudioRecorderの実時間を読み直す。保存時は音声ファイルの長さを優先 |
| 録音背景のcomputed propertyがレベルを親Viewで読む | `RecordingSheetBackground`へ分離し、音量の更新が録音シート全体に波及しないようにした |
| VoiceGlowが非アクティブ時にもTimelineを持つ | inactive・背景・Reduce MotionではTimelineを作らない。録音継続stripの装飾も同様に抑制 |
| finalizedが無制限、通常VStackとenumerated一時配列で全行を管理 | ライブ専用履歴を200文、各文2,000文字/約8KiBまでに制限。安定した単調増加IDとLazyVStack。揮発中の文も有界にし、切り詰めをUIで明示 |
| ライブ認識終了時のAnalyzerとcollectorの明示的終了が不足 | input tap/engine/streamを停止し、cancelAndFinishNowとcollector完了を待つ。次のライブ開始/保存後の認識は旧ライブの終了後に進む |

原音声と正式原文は削らない。ライブ履歴の制限は表示用のメモリだけで、正式な文字起こしは従来どおり保存音声から作る。ライブ停止はAudioSessionCoordinatorの録音claimを解除しない。着信・ルート変更・media service resetの既存処理と復旧draftの保存は維持した。

### バッファと単一パイプラインの評価

`LiveAudioBufferConverter` は入力形式が同じ場合にもtapの借用メモリを安全に所有するためコピーが必要。変換時の出力もAnalyzerへ所有権を渡した後の解放時点が公開されていない。出力のpool再利用は、解析中の音声を上書きする危険があるため採用しなかった。1入力につき1出力PCMBufferの割当を維持し、シリアルなtap所有とライフサイクルをコメントとテストで明確にした。

キューは16入力の上限を維持。overflowでライブ表示のstreamを失敗させてengineを片付け、AAC録音は続く。ロック・ブロック・ファイルI/Oをtapに追加していない。計測用signpostも256バッファに1回へ間引いた。

単一キャプチャーにすると、AACエンコード・書込み・割込み復旧をAVAudioEngine側で引き受ける必要がある。今回の実機品質比較ができない条件では既存AVAudioRecorderを置換しない。ライブ結果から正式原文を作る変更も採用しない。したがってライブ/正式認識の精度差、欠落、重複、時刻精度が改善したとは主張しない。

話者分離のモデルとmanagerは既存どおり関数ローカルで、actorにモデルを常駐させていない。モデル読込後にキャンセル確認を追加し、処理区間のsignpostを追加。FBankはcpuOnly、他はallという既存設定を維持した。CPU/GPU/Neural Engineの優劣は実機未測定なので変更していない。

## 5. ホストでのBefore/After

[生データ](qa/waiting-energy/host-audio.json)。同一Apple Silicon Mac、swiftc -O、同じ生成文（1文/秒）、同じ44.1kHz→16kHz PCM入力（4,096frames）、同じ16出力保持という合成負荷。旧converterはgitの`4dbc5fa`から取得し、旧表示履歴のappend方式と、新しい本番 `LiveTranscriptHistory` を比較した。

**15/60/120分は仮想入力の量であり、その時間マイクで実録音した測定ではない。SpeechAnalyzer、音声品質、端末バッテリー、実機の熱状態はこの計測に含まれない。**

| 仮想時間 | 保持文数 前→後 | 保持UTF-8 bytes 前→後 | Peak RSS MB 前→後 | CPU秒 前→後 |
| --- | --- | --- | --- | --- |
| 15分 | 900→200 | 501,190→111,400 | 10.44→9.91 | 0.0428→0.0406 |
| 60分 | 3,600→200 | 2,007,690→111,600 | 12.32→10.04 | 0.1564→0.1508 |
| 120分 | 7,200→200 | 4,016,490→111,600 | 14.93→10.08 | 0.3167→0.3092 |

RSSはgetrusage(RUSAGE_SELF)のホストプロセスPeak値。CPU秒はプロセスの累積CPU時間で、CPU使用率ではない。1回の短い合成測定なので数%のCPU差を速度改善の証明にはしない。有界な履歴保持は入力時間に依存しなくなったことを確認できる。

変換入力数は9,690 / 38,760 / 77,520。新実装の計数で1入力1割当を確認。同一形式のコピーを入力書換えから保護し、キューに保持した出力を再利用・破壊しないこと、16個を超える入力がoverflowになることも実行検証した。正式原文の長さはこの上限に制限されない。

再現コマンド:

```sh
MEMORA_CHECK_TMPDIR=/Volumes/WorkspaceSSD/Development/Agents/Codex \
  python3 -B tools/checks/run-audio-resource-checks.py --output /tmp/audio-resource-results.json
```

## 6. Instrumentsと実録音

`app.memora.audio` のProcessingカテゴリにLiveModelPreparation、LiveRecognition、SavedAudioTranscription、SpeakerDiarizationを追加。LiveConversionカテゴリはSampledBufferConversion。内容・記録ID・認証情報は記録しない。

待機fixtureを同一SimulatorのLight表示で15秒採取したTime Profilerの要約は `qa/waiting-energy/instruments-*.json`。raw trace/XMLはWorkspaceSSD側に保存している。統計的なsample weightは実時間の待ち時間、FPS、CPU占有率、電池消費とは異なる。DebugコードのUUID照合を追加したため、ランチャーだけ同じ別ビルドは拒否する。初回の古い集計器による「No app frames」は採用せず、修正後の採取だけを比較対象にする。

| 15秒の待機画面（同じfixture） | 変更前 | 変更後 |
| --- | --- | --- |
| sample数 / total sample weight | 730 / 730ms | 476 / 476ms |
| main-thread sample weight | 693ms | 462ms |
| symbolication | named | partial（1msのbacktrace欠落） |

旧traceにはThinkingGaugeのフレームがあり、新traceにはない。CPU負荷が減る方向の観測だが、1回の統計的な採取であり、録音・LLM実処理・電池の改善率には換算しない。計測時の新ビルドの `.debug.dylib` UUIDは `8DBF72ED-F167-30FA-AC16-99565AD328A2`、旧ビルドは `6D0904AA-C65D-3CFA-9321-F091151C6E93`。その後、展開したツール履歴の状態glyphを静的アイコンに整えたが、計測した折り畳み時の表示は同じ。

短時間録音E2Eは、実際のAVAudioRecorderで録音を開始し、省電力へ変更、一時停止・再開、シートを閉じて再度開き、同じAACとSQLite draftが保持されたまま保存されることを確認した。保存後にレコードが存在し、音声が空でなく、draftだけが解除されることを確認した。これは着信・Bluetooth切断・OS終了や120分の実録音の証明ではない。

最終の録音E2EではafinfoでもAAC/44,100Hz/monoを確認。長さ11.028027秒、477 packets、486,336 valid frames（+2,112 priming）だった。afconvertでPCMへ全体をデコードし、長さが0.001秒以内で一致することも確認した。検証用PCMだけを試験終了時に削除し、AAC原音声は維持する。Simulatorの入力であり、発話の欠落や音質の同等性を評価できる録音ではない。[結果](qa/waiting-energy/recording-audio.json)。

## 7. 回帰テスト・ビルド

GitHub Actionsと同じ6スイートをローカルで全Pass: next-generation、design-refresh、background-summary、summary-reliability、composer-layout、optimization。[結果](qa/waiting-energy/quality-six.json)。生ログは `/Volumes/WorkspaceSSD/Development/Agents/Codex/memora-quality-20261026-final/`。最後に計測器を修正した後も、影響するmotion/loadingスイートとprofile回帰テスト15件を再実行した。

- 拡張BackgroundSummaryExecutionChecks: 今回だけの送信、一度きりの消費、宛先不一致、分類済み禁止、許可の取消、原文・要約・workspace・モデルrevision・実効機密区分の変化を送信前/結果適用の両方で拒否、旧ジョブ自動再送拒否、端末内経路、継続許可/Agent/Webhookへ漏れないこと、実SQLite rollback/reopen。
- AudioResourceChecks: 15/60/120分相当の有界履歴、長大な結合文字列、PCM所有権・変換・キュー上限。
- test_waiting_audio_presentation.py: ゲージ/ロゴ/経過秒の撤去、承認待ち、Reduce Motion/背景の枝、外部送信Toggle撤去、非表示時のTask停止と録音独立性。
- Simulator profile tests: Debugコードの認識、UUID不一致、欠落、空/不正traceの拒否。
- 関連E2E 7件Pass: 待機fixture、待機→本文/承認/終端の遷移、生成操作、既存の生成モード、再開ジョブの保持、承認/保存2件。追加で録音E2EもPass。クラウドの送信先表示は設定を実際のUIでクラウドに切り替えた追加E2EでもPass。モデルAPIへの有料リクエストは使用していない。

Debugは `bitrig preview -platform iOS`、Releaseは `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release` でいずれも成功。[最終ビルド情報](qa/waiting-energy/build-validation.json)。Project.jsonプロジェクトにはXcode test targetがないため、`bitrig test -list -json` はexit 78。XcodeテストのPassとは報告せず、上記ホスト実行スイートとE2Eを使用した。

## 8. GitHub Actionsと実機の残課題

開始時のGitHub main `4dbc5fa` の [Actions run](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40247974012) はsuccess。今回の新コミットはpushしていないので、新SHAのリモートActions結果はまだない。ローカル6スイートPassをリモートCIのPassとは扱わない。

`xcrun xctrace list devices` で Ken’s iPhone はOffline。実機の電池消費、熱状態、Low Power Mode ON/OFF、Core ML computeUnits、ライブと正式認識の精度比較、話者分離あり/なし、長時間の背景安定性は未検証。実機が使える時に同一端末・同一音声・同一設定で次を実施する。

| 条件（各15/60/120分） | 今回の状態 |
| --- | --- |
| 録音のみ / 録音＋ライブ / 録音＋音量 / 全部 | コード経路調査と短時間の録音保存。実機の比較未実施 |
| 省電力録音 | 切替・pause/resume・保存のSimulator E2E。電池削減量は未測定 |
| 保存後の正式文字起こし | 経路維持とライブ終了待ち。実音声の認識精度比較は未実施 |
| 話者分離ON/OFF、computeUnits別 | 計測区間を追加。モデル設定を維持。実機未測定 |
| Low Power Mode ON/OFF、通常/高温 | ポリシーの全組合せをホストテスト。実機状態変化は未検証 |
| 画面表示中/背景 | 装飾とTimerの停止条件、録音画面を閉じた保存を検証。長時間背景録音は未検証 |

実機ではCPU使用率、Peak RSS、Allocations、キュー滞留、スレッド起床、熱状態、電池残量、処理時間、CER/WER、欠落区間、音声ファイルの整合性と背景録音の安定性を記録する。現時点で電池消費や文字起こし精度が何%改善したとの主張はしない。

## 9. 主な対応ソース

待機: ConversationStatusLine、ShimmerText、ThinkingTraceView、AgentActivityView、AIQuestionView、ProjectChatWaitingStatus、SearchView、AIComposerBar、WorkingStatus。

要約: SummaryGenerationSheet、SummarySubmissionIntent、LLMSelection、MemoraModel+SummaryGeneration、MemoraModel+BackgroundSummary、PendingSummaryJob、RecordAccessPolicy、RecordPrivacy、MemoraModel+RecordPrivacy、RegisteredLLMStore、MemoraModel+ModelSelection。

録音: RecordingPowerMode、MemoraModel+RecordingResources、MemoraModel+Capture、AudioRecorderService、RecordingLevelMeter、RecordingSheetBackground、CaptureSessionView、VoiceGlow、ActiveRecordingStrip、RealtimeTranscriptionService、LiveTranscriptHistory、RealtimeTranscriptView、SpeechRecognitionSettingsView、RootTabView、MemoraModel+Processing、TranscriptionService、FluidSpeakerDiarizationService、LiveAudioBufferConverter、AudioProcessingDiagnostics。

SpeechInputServiceとAudioSessionCoordinatorは調査のみ。録音中の音声入力拒否とtoken所有権を維持し、今回の省電力処理からsessionを解除しない。
