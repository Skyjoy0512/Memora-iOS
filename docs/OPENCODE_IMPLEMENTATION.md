# Memora — OpenCode 実装計画と進捗

レビュー指示書（A〜F）の実施状況を管理する。状態は 未着手 / 実装済み /
検証済み / 保留 の4つ。ビルドは Bitrig で都度確認し、実機・シミュレータで
確認できないものは「未検証」と明記する。

## 今回の改善反映

2026-11-02 Audio IntelligenceはCodexで直接段階実装。OpenCodeへの委託は行っていない。
BYOK構造化結果、録音の区間再開/容量監視、VAD評価基盤、長時間階層要約、
非公開のcloud予約/精算コアと費用計算を追加。実機品質/24時間/認証・購入・本番cloudは未完了。
詳細と未完了の条件は [統合報告](AUDIO_IMPLEMENTATION_REPORT.md)。

詳細と未完了項目は `IMPROVEMENT_BACKLOG.md` の「今回の追加反映」を参照。
要約・回答の読みやすさ、タスクの説明／取り組む日／進み具合、出来事の日付を使う
ジャーナル、追記を保つ週報を第一段階として反映した。
続いてAsk AIの期間全件集計と承認付きタスク一括更新、日／週の振り返り、
端末内だけのHealthKit読み取り、削除ジョブの原子保存、回答の資料保存を追加した。
新しいHealthKit設定を含むBitrigビルドは成功。シミュレータで日次振り返りへの
遷移・集計表示を確認した。HealthKit実データとクラウドモデルの新ツール実行は未検証。
終日イベント自己チェックの不正なテスト期間を修正し、シミュレータで成功表示を確認。
タスクの変更は保存成功後だけ反映し、AIの複数追加も一度の保存にまとめた。
無効な日付・対象外の会議・承認中のワークスペース変更は、追加せずエラーとして返す。
保存失敗と通知・Undo連動の実際の障害試験、クラウドツール実行は未検証。

## 2026-11-08 P1-1.1 メモの空タブ削除と添付資料リンク

`ProjectSourceAddSheet`から説明だけの「要約」「文字起こし」タブを削除。
`ProjectSource.attachedSourceIDs`を追加し、メモ作成時に同時に追加した資料を
同一プロジェクト・既存・重複なし・順序保持でリンク。資料詳細に「添付資料」を表示し、
詳細への導線と「添付を解除」を追加。解除はリンクのみ、資料は残す。資料削除時は
`pruningAttachmentLink`で他ノートのリンクだけを同一書き込みで外す。
状態: 実装済み・検証済み（host/シミュレータ）。後から添付、並べ替えUI、バックアップ復元E2Eは未検証。
検証: project-source-storage（リンク/重複排除/同一プロジェクト/reload/解除/非連鎖）PASS、
import/preparation PASS、pickers E2E PASS、`bitrig preview -platform iOS`成功。

## 2026-11-08 P0-2.4 取込→本文→検索→引用の実アプリ検証

Office検証を拡張し、 production の検索（`matchingSourceIDs`）、
`SourceContentSearch.context`（抽出本文参照/fingerprintスタンプ）、
`answerCitationTargets`、`AnswerSourceCitation.linked` を通して、
取り込んだ資料が検索で見つかり、引用が開けるリンクになることをアプリ内で確認。
モデル/外部API/ネットワーク不使用。`project-source-office.e2e.ts` が
iPhone 18 Pro MaxシミュレータでPASS。LLM実回答・実Web・実機は未検証。

## 2026-11-08 P0-2.3 失敗URL資料の再追加で同一IDを再試行

`addProjectLink`の重複経路で、既存が`.failed`のときだけ同じIDの準備を再スケジュールする。
ready/processing/unavailable、privacy、metadataは変更せず、二重レコードも作らない。
状態: 実装済み・検証済み（host）。実ネットワーク再取得は未検証。
検証: project-source-storage（再追加で同一ID・準備+1、ready重複は再取得なし）PASS、
preparation/import PASS、`bitrig preview -platform iOS`成功。

## 2026-11-08 P0-2.2 資料入口E2Eの更新と2件通過

現行UIへ `tests/project-source-pickers.e2e.ts` と `tests/project-source-office.e2e.ts` を更新。
表示切り替えメニュー→参考資料、参考資料を追加、ノートシートのタイトル/保存、
資料を追加メニュー（写真/ファイル）へ合わせた。iPhone 18 Pro Maxシミュレータで
ピッカーキャンセル時の入力保持と、Office3形式の取込→本文再読込→SQLite一致→削除を確認（2件PASS）。
専用フィクスチャのみ使用。残: photo/recovery/interruption E2Eは旧前提のまま、
要約/AskAI/引用/再起動を通すE2Eは未追加。

## 2026-11-07 P0-2.1 資料引用リンクの末端接続

通常AskAIで検索・送信したProjectSourceが回答内マーカーから開けるリンクに変換されず、
許可集合で落ちていた。`answerCitationTargets`へ`message.sourceCitations`由来の資料を
追加し、`ProjectCitation`へ抽出本文参照/内容fingerprintを任意保存、`ProjectCitationTargets`で
不一致・未読・削除を無効化した。保存回答も同じリンクと`sourceProjectFileIDs`を保持し、
`documentCitationTarget`で未読資料を拒否する。

状態: 実装済み・検証済み（host）。実サービス/実機の回答品質は未検証。
検証: inline citation（スタンプ・失効・保存リンク）PASS、conversation evidence /
attachment citation / source summary / source intake PASS、`bitrig preview -platform iOS`成功。
残: 入口別E2Eの実データ貫通、旧UIラベル依存のsource E2E更新、ノート編集後の要約再生成。

## 2026-11-07 P0-1.4 live文字起こしを録音入力へ一本化

`RealtimeTranscriptionService`の独自engine/tapを削除し、録音の`RecordingMicrophoneInput`
を唯一のマイク入力にした。`LiveAudioInputFeeder`が44.1kHz/monoをanalyzer形式へ変換し、
録音tapが`consume`で流す。準備前/停止後/満杯は破棄し録音は継続。`consume`はnonisolated。
省電力停止・再開では新しいfeederを同じtapへ差し替える。

状態: 実装済み・検証済み（host）。実機のSpeechAnalyzer入力/遅延/二重tapなしは未検証。
検証: recording start / audio resource / optimization 各runner PASS、
`bitrig preview -platform iOS`成功（既存警告のみ）。
付随修正: `run-meeting-persistence-performance-checks.py`のsource一覧に
`RecordingAudioPart`/`RecordingAudioManifest`を追加（既存の未同梱で失敗していた）。

## 2026-11-07 P0-1.3 実マイク→分割writer接続

通常録音を実マイク入力＋15分分割writerへ切り替えた。
`AudioRecorderService.prepareRecording()`で録音ID/最初の原本を決め、モデルがmanifestと
下書きを永続化してから`startContinuous()`でtapを開始する。15分境界は
`admitRecordingRotation`のSQLite同期commit後に次の原本を作成。停止は
`stopContinuous()`でtap除去→drain→確定manifest返却、モデルが下書きへ反映して既存の
検査/SQLite確定へ渡す。取消はdrainせず破棄。声紋登録は従来のAVAudioRecorderを維持。

状態: 実装済み・検証済み（host）。実マイクtap、AAC境界、割り込み、24時間、RTF/CERは未検証。
未対応: live文字起こしは別engine/tapのまま（録音入力との共有は次）。
検証: chunk writer / recording start / finalization / recovery / media / checkpoint
service / run coordinator / microphone input 各runner PASS、`git diff --check` PASS、
`bitrig preview -platform iOS`成功（既存警告のみ）。

## 2026-11-07 P0-1.2 実マイク入力の所有と変換

`RecordingMicrophoneInput`（`App/RecordingMicrophoneInput.swift`）と
`RecordingInputContinuity`（`App/RecordingInputContinuity.swift`）を追加した。
録音runごとに1つの`AVAudioEngine`入力tapを所有し、実フォーマットを
44.1kHz/mono/非interleaved Float32へ変換して所有bufferをrecording sinkへ渡す。
独自session・2つ目のtapは作らない。sampleTimeのgap/duplicateを検出する。
**`startCapture`への接続は当時未実施**（P0-1.3で接続済み）。

状態: 実装済み・検証済み（host）。実機tapと接続は未検証。
検証: `bash tools/checks/run-recording-microphone-input-checks.sh` PASS、
既存の録音系runner PASS、`bitrig preview -platform iOS`成功（既存警告のみ）。
次: P0-1.3（開始前manifest永続化、writer接続、停止drain、自動rotation）。→ P0-1.3で実施。

## 2026-11-07 P0-1.1 録音runの状態保護

`RecordingRunCoordinator`（`App/RecordingRunCoordinator.swift`）を追加し、
`AudioRecorderService`のstart/stop/失敗/media services resetへ接続した。
preparing→recording→stopping→finalizing→savedをrunIDで保護し、二重start/stop・
古いcallback・準備中の取消を拒否する。記録のSQLite確定は既存の
`stopCapture`→`commitRecordingSave`のまま変更していない。

状態: 実装済み・検証済み（host）。実機の割り込み/二重操作は未検証。
変更: `App/RecordingRunCoordinator.swift`（新規）、`App/AudioRecorderService.swift`、
`tools/checks/RecordingRunCoordinatorChecks.swift`（新規）とrunner、関連docs。
検証: `bash tools/checks/run-recording-run-coordinator-checks.sh` PASS、
既存のchunk writer / recording start / recording media / recording recovery /
source extraction cache各runner PASS、`git diff --check` PASS、
`bitrig preview -platform iOS`成功（既存警告のみ）。
次: 実マイク入力を44.1kHz/mono/Float32へ変換してwriterへ渡す接続と停止drain。

## フェーズ

状態は `docs/IMPROVEMENT_BACKLOG.md` と同じ4つ（未着手／実装済み・未検証／
検証済み／保留）。過去のフェーズはビルド成功のみで、実行確認は未検証。
今回確認した日次振り返りの導線と表示、自己チェックは上記の検証記録を参照。

| フェーズ | 内容 | 状態 |
| --- | --- | --- |
| 0 | 基準作成（ブランチ・差分・ビルド・既知の回帰・未検証条件の記録） | 実装済み・未検証 |
| 1 | 誤表示・危険操作の解消（A01〜A06, A10、偽の成功表示） | 実装済み・未検証 |
| 2 | 保存・媒体・ジョブ基盤（A07〜A09, A11, B01〜B04、バックアップ、サービス分離） | 実装済み・未検証 |
| 3 | 録音を見返して整理（B05〜B12, D01〜D13, E01〜E07） | 実装済み・未検証 |
| 4 | 根拠付きAI（C01〜C13, E08） | 実装済み・未検証 |
| 5 | 性能・アクセシビリティ（F01〜F10, E04・E05・E10） | 実装済み・未検証（性能の数値は未計測） |
| 6 | TestFlight準備（実サポートURL・実機確認） | 未着手 |
| 7 | 改修後レビュー（2回目）の10項目 | 実装済み・未検証（順序・失敗の一部はDEBUG自己チェックで検証） |

## フェーズ0：基準

- ブランチ: `main`。作業ツリーは各コミット後にクリーン。
- ビルド: Bitrig で全変更後に成功（診断なし）。
- 既知の回帰（`AGENTS.md` に記録）: タブバーの `UISegmentedControl`、
  ファイル画面上部のスクロール連動表示、ジャーナルの主スクロールビュー。
- 未検証: 内蔵シミュレータが状態APIを返さず（`does not support simulator
  state`）、実操作・録画による確認ができない期間がある。UIの見た目・操作は
  実機/シミュレータでの確認待ちとして残す。
- 実装済み（前段）: 録音破棄、カレンダーのスワイプ、composer入力の保持、
  写真のトリミング/加工、改善一覧（A01相当の一部）。

## フェーズ1：誤表示・危険操作の解消

| ID | 内容 | 状態 |
| --- | --- | --- |
| A01 | 開発用リセットを `#if DEBUG` に限定し、コピーを実態に合わせる | 一部 実装済み（デモと実データの完全分離はフェーズ2） |
| A02 | 文字起こし失敗時にサンプル本文を保存しない／失敗理由と再試行を表示 | 実装済み |
| A03 | 要約・決定・タスクの固定文を廃止し、実文字起こしから生成 | 実装済み |
| A04 | 世代ID・キャンセル・削除後の更新拒否・タスク重複の解消 | 実装済み（処理ジョブの永続化はフェーズ2） |
| A05 | 録音破棄・会議削除で音声ファイルを削除し、失敗を通知 | 実装済み |
| A06 | データなし／破損を区別し、破損は退避して通知 | 一部 実装済み（移行失敗の扱いはフェーズ2） |
| A10 | Keychain更新を成功後にキャッシュ更新、失敗時は既存を維持 | 実装済み |
| 偽の認証／購入／同期 | 未実装の操作を成功扱いしない | 実装済み |
| 架空の引用・モデル表示・共有説明 | 実在の根拠のみ表示 | 実装済み |

### 変更したファイル（フェーズ1）

- `App/TranscriptionService.swift`（`failed(String)` を追加、クラウドの失敗理由を区別）
- `App/MemoraModel.swift`（サンプルfallback廃止、世代ID、音声削除、破損データ退避、失敗通知）
- `App/MediaFiles.swift`（新規：管理領域のファイル削除）
- `App/KeychainStore.swift`（更新成功時のみキャッシュ更新）
- `App/SummaryTemplateMarket.swift`（テンプレートを生成指示へ接続）
- `App/SettingsView.swift`（開発用リセットを Debug 限定、表記修正、バージョンはBundleから）
- `App/BundleVersion.swift`（新規）
- `App/ContentView.swift`（読み込み失敗・削除失敗の通知）
- `AGENTS.md`

### 未解決・保留

- 破損データは `<key>.unreadable` へ退避するだけ。復旧・書き出しの導線は
  フェーズ2（バックアップ）で用意する。
- A01のデモと実データの完全分離は、独立ストア（A07）と同時に行う。
- 実機/シミュレータでのUI確認は未検証のまま。

### フェーズ1（後半）の変更

- `App/AuthView.swift`: サインインは未接続であることを明示。プロバイダーボタンは
  ローカルのアカウントを作らず案内を表示する。
- `App/PaywallView.swift`: 購入・復元は未接続の案内のみ。価格は未定とし、
  ローカルの購読フラグを立てない。`startSubscription()` は呼ばない。
- `App/SettingsView.swift`: 「同期します」「あと4回…」など実態と異なる説明を削除。
- `App/MeetingShareText.swift`: 端末内リンクを共有本文から外す。
- `App/MeetingDetailView.swift`: リンクの説明を「この端末の記録へのリンク」に。
- `App/MemoraModel+AI.swift`: 架空の決定・タスク・引用を含む定型回答を廃止し、
  エンジンが使えないときはその旨を返す。
- `App/AIComposerBar.swift` / `App/EngineChoices.swift` / `App/AIQuestionView.swift`:
  composerは実エンジン（`AIEngine`）を表示・切替。`AIModel.swift` は削除。


## フェーズ2：保存・媒体・ジョブ基盤（今回）

| ID | 内容 | 状態 |
| --- | --- | --- |
| A07 | システムSQLiteのローカルストア（`LocalStore`）へ移行。設定はUserDefaultsのみ。写真もファイル参照 | 実装済み |
| A08 | 音声を管理フォルダ相対の参照で保存・解決。旧絶対URLは実在する管理内ファイルのみ引き継ぐ | 実装済み |
| A09 | 削除のごみ箱化（30日復元） | 実装済み |
| A11 | 実行中の処理を永続化し、起動時に中断を検出して再試行表示 | 実装済み |
| B01〜B04 | 録音状態の明示化、AudioSessionの一本化、割り込み、下書き保存 | 実装済み（B02は録音中の音声入力拒否まで） |

### 変更したファイル（フェーズ2）

- `App/LocalStore.swift`（新規）: システムSQLite（`documents`テーブル、トランザクション書き込み）。
  起動時に同期ロードする必要があるため、actorではなくロックで直列化している
  （actor化は起動の非同期ロード化とセットで次段）。
- `App/MediaFiles.swift`: 参照（相対パス）と解決、削除。
- `App/Meeting.swift`: 音声URLを相対参照で保存するCustom Codable（旧絶対URLの移行つき）。
- `App/MemoraModel.swift`: ストアへの読み書きとUserDefaultsからの移行（旧値は削除せず残す）、
  保存失敗の通知、処理ジョブの永続化と中断検出。
- `App/ContentView.swift`: 保存失敗の通知。

### 移行の扱い

- 初回起動時、ストアに無いキーだけUserDefaultsから読み、ストアへ書き込む。
  **UserDefaultsの旧値は削除しない**（切り戻し可能にするため）。
- 読み込めないドキュメントは `<key>.unreadable` としてストアに退避し、通知する。

### フェーズ2（追加）

- B01: `isPreparingCapture` / `isSavingCapture` を導入し、開始・終了の再入を防止。終了ボタンは保存中に無効化。
- B02: 録音中は音声入力を理由付きで拒否し、共有AudioSessionを録音に譲る。
- B04: 録音下書き（ファイル名・タイトル・ノート・開始時刻）を永続化し、起動時に中断を検出。音声があれば「復旧した録音」、無ければメモとして回収。

### フェーズ2（追加2）

- A09: 会議の削除をごみ箱（`TrashedRecord`）へ変更。記録・タスク・ジャーナル項目をまとめて保持し、復元はそのまま戻す。30日経過で音声ごと自動削除、完全削除は確認つき。設定 →「最近削除した項目」から操作する。

### フェーズ2（追加3）

- A07 完了: 会議の写真を `Photos/` 配下のファイル参照に変更（`Meeting.photoFileNames`）。旧レコードのインライン写真は読み込み時に書き出して移行。完全削除・期間経過で写真ファイルも削除。

### フェーズ2（追加4）

- バックアップ: `BackupPackage`（版付き`manifest.json`＋`media/`のフォルダパッケージ）で書き出し・復元。復元は**記録が空のときだけ**許可し、破損・版不一致・重複ID・媒体欠落・不正なファイル名を検査。APIキーは含まない。設定 →「バックアップ」から操作。
- AI履歴を永続化（`memoraAIHistory`）。バックアップの対象にも含めた。
- 音声参照の解決: 相対名は参照としてそのまま解決し、旧絶対パスだけ実在チェックする方式に整理（復元時に媒体を先に展開できるようにするため）。

### フェーズ2（追加5）

- B03: `AudioRecorderService` が割り込み・経路変更（`.oldDeviceUnavailable`）・メディアサービスリセットを監視。割り込み時は録音を一時停止し、画面に理由を表示して利用者が「再開」できる。リセット時はここまでの録音を保存して終了。セッションは再開時に再アクティブ化する。

### フェーズ2（追加6）

- F07（一部）: ドキュメントの読み書きを `RecordStore` サービスへ集約。モデルは `LocalStore`・`UserDefaults`・保存キューを直接扱わなくなった（旧データの移行も `RecordStore` 内）。バックアップの一時領域もモデル側で決め、画面から `FileManager` を触らないようにした。
- 残り: 処理ジョブの専用サービス化、画像処理（`PhotoEditorView`）の分離。

### フェーズ3（着手）

- B05: `AudioPlayerService` を追加（AVAudioEngine＋AVAudioPlayerNode＋時間ピッチで速度変更）。会議詳細に見出し下の再生バー（再生/一時停止・位置・15秒・速度0.5〜2倍）。録音中は再生せず、画面を離れると停止。

### フェーズ3（追加2）

- B06: 詳細の文字起こしで、発言の時刻をタップするとその位置から再生し、再生中の行を淡い背景で強調。時刻が入っていない文字起こし（時刻0のみ）では時刻をボタンにしない。

### フェーズ3（追加3）

- D01: ファイル検索の24件打ち切りを廃止（通常一覧のみ24件）。検索中は件数を表示。
- D02（一部）: 検索対象を全画面で統一（タイトル・ノート・要約・文字起こし・決定事項・未決事項・重要なポイント）。
- D03: プロジェクトの名前変更（`RenameSpaceSheet`）・削除（会議は未分類へ）・会議の所属変更（`SpacePickerSheet`、詳細の「プロジェクト」から）。

### フェーズ3（追加4）

- D05: タスクを編集できるように（`TaskEditView`: タイトル・担当・期限の有無・元会議、削除は確認つき）。期限切れは「期限切れ」と赤で表示し、期限なしはトグルで区別。タスク一覧では本文タップで編集を開く（完了トグルは従来どおり）。

### フェーズ3（追加5）

- D04: ジャーナル記録の詳細（全文＋写真の拡大表示）、編集（タイトル・本文・日時／日時変更でその日へ移動）、削除（`TrashedLifeLogEntry` で30日復元可、完全削除で写真も削除）。タイムラインの記録をタップで開く。
- A07の残り: ジャーナル写真もファイル参照化（旧インラインは移行）。人物の写真は次段。

### フェーズ3（追加6）

- D06: `DraftStore` と `InlineMarkdownEditor.draftKey` を追加。要約・ノートの編集中テキストを800msのデバウンスで保存し、次に開いたときに「書きかけの内容を復元しました」と表示して復帰。確定時に下書きを削除。
- 併せて `SelfChecks`（DEBUG限定・起動時）を追加し、Markdown往復と下書き保存の往復を検証（失敗はログ）。正式なテストターゲットは bitrig-standard-project の手順が未確認のため保留。

### フェーズ3（追加7）

- B07: `MemoraRecordingAttributes.ContentState` に `pausedElapsed` を追加し、`startedAt` を実経過時間に合わせて再アンカー。ウィジェットは録音中はライブタイマー、一時停止中は凍結した時間と「一時停止中」を表示。起動時に残っているActivityを終了する（録音は自動再開しないため）。

### フェーズ3（追加8）

- B08: 録音シートの文字起こしタブに説明（「録音を終えると文字起こしします」）を表示。
- B11: `ActiveRecordingStrip` を独立ファイル化し、ジャーナル・タスク・Ask AIにも表示（ファイルは既存）。録音中であることと経過時間が見え、タップで録音画面に戻れる。

### フェーズ3（追加9）

- B09: `importAudio` を書き直し。コピーと検査を `Task.detached` でメインアクター外へ。一時名でコピー→`AVURLAsset` で再生可能性と実長さを取得→確定名へ移動（失敗時は一時ファイルを削除）。進捗は `Double?` になり、実測できない間は不定表示。
- B10: `CloudTranscriptionService` をファイルベースのアップロード（`URLSession.upload(fromFile:)`）に変更。OpenAIはmultipartを一時ファイルで組み立て、Deepgramは本体を直接送信。MIMEは拡張子から決定。上限（OpenAI 25MB／Deepgram 2GB、各公式仕様）を送信前に検査し、超過は理由を表示。

### 改善指示書（3回目）フェーズ2-2（T02）

- **T02（実装済み・未検証）**: `SpeechTranscriber` を明示オプションで構築し、`reportingOptions` から `.volatileResults` を外した（保存済み音声は確定結果のみ）。`attributeOptions: [.audioTimeRange]` を維持。
- 確定結果を1件ずつ行にする `SpeechTranscriptionSegments.segment(from:)` に置き換え。**統合・削除をしない**（近接時刻・同一文言を保持）。
- `SpeechTranscriptionCollapse`（全途中結果の蓄積と推測的な統合）とその自己チェックを削除。自己チェックは「確定のみ・空を除く・近接や同一文言を保持・時刻保持」に置き換え。
- `TranscriptionOutcome` に `.nothingRecognized`／`.cancelled` を追加し、モデル側で区別して扱う（キャンセルは未開始に戻し、いずれも音声は保持）。
- 次段: T03。

### 改善指示書（3回目）フェーズ2-1（T01）

- **T01（実装済み・未検証）**: 起動時に既存の文字起こしを書き換える自動修復（`SpeechTranscriptionCollapse.repair` と
  `MemoraModel` の起動時ループ）を**削除**。保存済みの文字起こしは起動で変化しない。話者・手編集・生成元を見ない
  推測的な統合は行わない。修復の将来仕様（原文退避・差分確認・明示的適用・取り消し）はバックログに記録。
- 次段: T02（確定結果のみで組み立て）、T03（収集Taskの終了と失敗の区別）。

### 改修後レビュー フェーズ4（音声セッションの競合）

- `AudioSessionCoordinator` を追加。録音・再生・音声入力の**使用権を1か所で管理**し、**録音が最優先**（録音中は他機能がセッションを取れない）、**所有者だけが解放できる**（`release` は `.recording` を受け付けず、録音は `endRecording()` でのみ終了）。セッションの無効化は所有者がいないときだけ。
- `AudioRecorderService` は開始時に使用権を取り（失敗時は解放）、停止時に終了。`AudioPlayerService.play()` は取得できなければ**理由を表示して再生しない**。`SpeechInputService` は**権限確認のawait後に**取得を再確認し、`stop` は自分の所有時のみ解放（テキスト送信・画面終了で録音を止めない）。
- 自己チェック: 空き状態の取得、他機能保持中の拒否と理由、非所有者の解放が効かないこと、録音中の音声入力拒否、録音終了後の取得を検証。

### 改修後レビュー フェーズ3（処理ジョブと録音復旧）

- 入力リビジョン: 文字数ではなく**本文・話者・時刻そのもの**をハッシュする（同文字数の編集も検知）。要約生成時は**開始時の要約も記録**し、生成中に手編集されていたら適用しない。
- 破棄・キャンセル時の状態: 入力不一致・手編集・キャンセルでは**古い結果を適用せず `.waitingForSummary` に戻し**、再生成できる状態にする（処理中表示を残さない）。
- 実行識別子: `ProcessingService` は記録ごとに**再発行されない実行ID（UUID）**を持ち、結果適用も終了処理（tasks／activeIDsの解放）も**自分の実行IDが一致するときだけ**行う。`cancel` でIDを消す方式をやめ、遅れて終了した旧ジョブが新ジョブの管理状態を壊さない。
- 文字起こし開始の一本化: `startTranscription(_:)` は**音声の有無と実行中かどうか**で判定し、取り込みファイルと**復旧録音**が同じ経路を使う。復旧録音の詳細画面に開始ボタンと説明を表示（録音・クラウド送信は自動再開しない）。
- 自己チェック: 実行IDの所有権を**ゲートで順序を固定**して検証（旧ジョブ開始→キャンセル→新ジョブ開始→旧ジョブ終了→新ジョブが実行中のまま／その後キャンセル可能）。

### 改修後レビュー フェーズ2（AIの参照範囲・根拠・送信内容）

- 送信内容を `MemoraModel.requestContent(for:scopeLabel:allowedMeetings:tasks:)`（**純関数**）に集約し、**範囲外の記録・タスクを文脈に含めない**。順位付け・文脈生成・添付処理は共通基盤 `answer(request:...)` が担い、チャットと詳細画面で同一。
- `AIQuestionRequest` を追加し、**送信時点の質問・範囲・添付を固定**（`AIQuestionView` は request を受けて開始し、処理中のUI変更に影響されない）。画面終了でタスクをキャンセルし、古い結果は適用しない。
- `AIQuestionView` の **固定時刻「00:42 の発言」を削除**し、保存済み文字起こしから一致した発言と実時刻のみ表示。**失敗時は根拠セクションを出さず**、失敗メッセージのみ表示。
- 添付は対応形式（テキスト／PDF）の内容を実際に文脈へ入れ、非対応は「送信していません」と明示。
- `QuickAIComposer` は**送信時に `AIQuestionRequest` を組み立ててから**シートを開き、入力欄のクリアは受付成功後のみ。
- 自己チェック: 会議Aへの質問に会議Bの内容が混ざらないこと、プロジェクト範囲が範囲外記録を運ばないことを検証。

### 改修後レビュー フェーズ1（保存・バックアップ・復旧）

- 媒体パス検証: `MediaFiles.isPlainName`（空・`.`・`..`・区切り・NULを拒否）と `isInside`（symlink解決後の**厳密な子**判定。フォルダ自身や `RecordingsOld` のような前方一致は不可）を追加し、`reference`／`resolve`／`photoURL`／`delete` を通した。
- ストア: `LocalStore.ReadOutcome`（missing／data／failed）と `writeBatch`（1トランザクション）を追加。`RecordStore` は **全書き込みを同一キューで直列化**（`saveNow`／`saveBatch`／`remove` は待つ）、`load` は **absent／failed を区別**し、UserDefaultsからの移行は**マーカーで一度だけ**、隔離は**退避成功時のみ元を削除**。
- 読込失敗時は `isStoreProtected` を立て、以後の保存を拒否して既存データを上書きしない（再起動を案内）。
- ゴミ箱への移動／復元は **会議・タスク・ジャーナル・ゴミ箱を1回の書き込み**に統一。録音復旧は**復旧レコードの保存成功後にのみ下書きを削除**し、失敗時はメモリ上の挿入を取り消して下書きを残す。
- バックアップ: **ジャーナル写真も収集**。原本は必須（欠落・コピー失敗は明示して失敗）、**サムネイルは再生成可能**として任意。出力先は**毎回一意**（日時＋UUID、失敗時は削除）。復元は **stagingで全ファイル検証 → 配置 → 記録を1回の書き込み**、記録書込失敗時は配置済み媒体を撤回。
- 下書きは `RecordStore` 経由に統一（順序保証）。

### フェーズ5（追加26・自己チェック追加）

- `SelfChecks` に、処理の入力リビジョン（文字起こしの指紋が安定で、編集を検知する）、写真のサムネイル命名（`photoFiles` が対で返す）、状態フィルターの対応（完了＝ready）を追加。DEBUG起動時に検証する。

### フェーズ5（追加25・F06の残りとF10の計測手段）

- F06: `MeetingPDF.write(meeting:tasks:onProgress:)` を async 化。本文の描画はメインアクター、ページ生成は `Task.detached` でオフメイン。ページごとに進捗を返し、`Task` キャンセルで中断（`ExportError.cancelled`）。詳細画面は進捗カード（％と「キャンセル」）を表示。
- F10: 計測ビューに「計測を実行（検索20回）」を追加。読み込み済みの件数に対して検索パスを繰り返し計測し、p95 を読めるサンプルを記録する（測定対象はマッチング処理で、その後の画面描画は含まない）。
- 実測は引き続き**未実施**（同一実機での比較が必要）。

### フェーズ5（追加24・F08〜F10）

- F08: `OmiPairingManager` に `wantsScanning` を追加し、`centralManagerDidUpdateState` は状態の反映のみ（検索中のときだけ再開）。周辺機器の参照を停止・切断時に解放。下書き保存タスクも完了時に nil 化。Task寿命は各サービスで解放を確認。
- F09: `App/EngineAvailability.swift` を追加（OS対応／対応言語／モデル準備／キー有無）。文字起こし設定とAI設定に「この設定での状態」、文字起こしはジョブ開始前のプリチェック。
- F10: `App/PerformanceLog.swift`（`PerformanceLog.shared`、上限500件、LocalStoreに保存）と `PerformanceLogView`（DEBUG）。起動・検索・保存（録音確定・会議の引き渡し）・画像デコード・処理を計測。検証データの生成（100／1,000件）はDEBUGのみ。
- **性能の実測は未実施**（同一実機・同一ビルドでの比較が必要）。

### フェーズ5（追加23・F07）

- `App/ProcessingService.swift` を追加。記録ごとの**世代**（`begin`）、**現在性の判定**（`run(work:apply:)` は現在の世代のときだけ `apply`）、`cancel`（世代とTaskを破棄）、`activeIDs`（実行中ジョブ）を保持。終了時は `end` で Task 参照を解放。
- `MemoraModel` は `processing.run` で文字起こし・要約を実行し、適用はサービスに委ねる。`deleteMeeting` は `processing.cancel`。中断ジョブの永続化（`memoraActiveJobs`）は従来どおりモデルが担当し、形式・キーは不変。
- 要約は `ProcessingService.inputRevision`（文字起こしの指紋）を生成時に記録し、適用時に照合するため、生成中の編集結果を上書きしない。
- 一時PDFの後始末を `MeetingPDF.discard` に移し、画面からファイル操作を排除（タスクの自動生成は元々無いため重複作成なし）。
- 不変条件は維持: 削除・再試行・キャンセルで旧結果を反映しない／再起動後に中断を検出して再試行／完了・失敗・キャンセルでTask解放。

### フェーズ5（追加22・F01〜F05）

- F01: `ImageDownscale.downsampled(at:maxPixelSize:)`（ImageIOのサムネイル生成）と `MediaImageCache.image/photo`（非同期・サイズ別・上限80）。`LifeLogRow`・写真ストリップ・拡大表示が利用。不要になった `photoData`／`photoThumbnailData` を削除。
- F02: `updateMeeting` と文字起こし編集で記録単位に検索テキストを無効化。`meetings` の didSet は消えたIDの間引きのみ。
- F03: `rebuildMeetingAggregates()` でプロジェクト別（件数・最新4件アイコン・最新日時）と人物別（件数・一覧）を1回の走査で集計。
- F04: `rebuildLifeLogDays()` で日別インデックスを構築し、`NSCalendarDayChanged`・`NSSystemTimeZoneDidChange`・`UIApplication.significantTimeChangeNotification` で更新。
- F05: `RecordingLevelMeter` に音量を分離。キャプチャ画面の表示中のみ45ms間隔でサンプリングし、非表示時は300ms（録音は継続）。
- 性能は**未計測**（F10の計測手段が未実装のため）。バックログでは「実装済み（性能未検証）」として残す。

### フェーズ5（追加21・E02/E04/E10の残りと性能）

- E02: 入力中の質問を `MemoraModel.composerDraft` が持ち、600ms後に `DraftStore` へ保存、起動時に復元。`QuickAIComposer` はローカルStateをやめた。
- E04: 添付メニュー・エンジン選択・送信・添付解除・再生の15秒送りを44ptのタップ領域に（描画サイズは維持）。
- E10: 明暗は意味的な色（systemBackground／label／secondary）で構成されていることを確認（目視は未実施）。
- 性能: `MediaImageCache`（NSCache）で一覧・拡大のデコード結果をファイル名キーで再利用。`meetingPhotoThumbnails` は不要になり削除。F02（検索キャッシュの一括破棄）は既に `meetings` の didSet で実施済みと確認。
- ※ F01・F03〜F05・F08〜F10 は原文が未共有のため未着手のまま記録。

### フェーズ4（追加20・E03・E06〜E10）

- E03: `BottomBarScrollBehavior` は画面IDを受け取り、モデルの `bottomBarHiddenScreens` に自分の分だけ記録。`RootTabView` は表示中のタブのIDだけを見る。VoiceOver使用中は隠さない。
- E06: `handle(url)` は存在しないIDで遷移せず `MissingRecordNotice` を出し、ごみ箱にあれば開く導線を提示。共有本文は端末内リンクを自動付加しない（従来どおり）。リンクのコピーは「この端末の記録へのリンク」と説明。
- E07: `MeetingPDF` をA4・複数ページ・ページ番号・一意な一時名に。`ActivityView` の完了で一時ファイルを削除。失敗はアラート。
- E08: `NotionService.save` はページ作成＋100ブロック単位の追記、`Outcome`／`PartialPageFailure` で結果とURLを返す。`unknownOutcome` は自動再送しない。詳細画面は保存中表示と「開いて確認」。
- E09: ヘルプ／プライバシーは準備中表示（example.comを削除）。`EmailAuthView` はアカウントを作らず「接続されていません」と説明。バージョンはBundleから。
- E10: インライン編集とジャーナルの記録タップにボタン特性・ヒント・名前付きアクションを追加。

### フェーズ4（追加19・C01〜C13の残り）

- C01: `meetings(in:from:)`／`openTasks(in:from:meetings:)` でスコープを先に絞り、`SelfChecks` で範囲外が混ざらないことを検証。
- C02: 根拠には実際に送った記録と、保存済み文字起こしからの一致1行（時刻つき）のみ。`aiContext` にも根拠発言として同じ行を入れる。
- C03: `AIAttachmentText`（テキスト／PDFのみ、8,000字上限）。非対応形式は回答前に「送信していません」と明示。
- C04: `aiEngine`／`aiProvider` をモデルが所有し、`AIEngineService` は引数で受ける。設定に「実際に使う」を表示、未対応は選択不可。
- C05: `RecognitionLanguage.automatic` を「端末の言語」に改称し、端末Localeで処理することを明記。
- C06: `sendAIChat` が Bool を返し、composerは受理時のみクリア。
- C07: 会話ID・要求IDで所有権管理、旧タスクをキャンセル、直近6往復を履歴として送信。
- C08: `AIHistoryView` は詳細（質問・回答・対象・エンジン・日時）を開く。再質問は「もう一度聞く」、削除はスワイプ。
- C09: `AIAnswerFailure`／`AIAnswerResult` で失敗理由を区別（キャンセルは非表示）。
- C10: `AIAnswerDetails` を表示、「思考を表示」を廃止。
- C12: 最下部付近のみ追従、それ以外は「新しい回答」ボタン。
- C13: `StreamingText` はタスクをキャンセル可能にし、長文・確定後は選択可能な `Text`。
- 併せて修正: `startImportedTranscription` が失敗時にサンプル文字起こしを保存していたのを、理由を残して音声を保持する形に（A02/A03の趣旨）。

### フェーズ4（追加18・根拠付きAIの基盤）

- `MemoraModel+AI`: `aiSources(for:scope:)` が質問の語で記録を検索して最大5件を選び、`aiContext(for:)` はその記録だけ（要約・決定・未決・発言抜粋）＋未完了タスクを文脈にする。`questionWords` は日本語を2文字単位に分割（`SelfChecks` で検証）。スコープ（すべて／ファイル／プロジェクト）を反映。
- `AIChatMessage.sources` と `AIChatSource` を追加し、`AIMessageView` が「参照した記録」を表示、タップで `MeetingDetailView` を開く。エンジン未接続の断りには参照を付けない。
- `AIQuestionView` も同じ検索結果を文脈に使う。

### フェーズ3（追加17・アクセシビリティ点検）

- 読み上げ: `MeetingRow`／`TaskRow`／`LifeLogRow` を1つのアクセシビリティ要素にまとめ、表示順ではなく意味の通るラベルに。タスク行には「タスクを編集します」ヒントとボタン特性を付与。写真有無・担当・期限切れ・元記録も読み上げに含める。
- 通知: `MemoraModel.announce(_:)`（`UIAccessibility.post`）で、録音開始・録音保存・文字起こし完了／失敗・要約完了／失敗・マイク権限拒否をアナウンス。
- ※ E03・E06〜E10 の元の要件文は未共有のため、上記の点検項目として記録。

### フェーズ3（追加16）

- D10: `UpcomingMeetingCard.refresh()` は loading 以外でも実行でき（`isLoading` で多重実行だけ防ぐ）、`.task`・`scenePhase` 復帰・`EKEventStoreChanged`・再接続から呼ぶ。設定で権限を変えても復帰時に反映。
- D11: `startCapture(event:)` が予定を受け取り、タイトルを予定名で初期入力（そのまま編集可）。`Meeting.calendarEventID` を追加し、その録音から作られた記録にのみ保存、保存・破棄時に消去。録音シートに元の予定を表示。

### フェーズ3（追加15）

- D12: ジャーナルの空状態が選択日を語るようにし（今日／他日）、カレンダーへ「今日」・前週／次週（月表示では前月／次月）ボタンを追加。日セルの読み上げに記録の有無を追加。

### フェーズ3（追加14）

- D09: `updatePerson`（名前・メモ、旧名を使うタスク担当の追従）と `mergePerson`（参加者参照の付け替え・重複除去、担当名の更新、写真の引き継ぎ、記録は残す）を追加。`PeopleManagerSheet` から行タップ／スワイプで `PersonEditSheet` を開き、統合は確認ダイアログで件数を提示。
- D13: 添付メニューの「カメラで撮影…」と `CameraCaptureSheet` を削除（撮影は未実装のためTestFlightに出さない）。写真を選択・音声・ファイルは従来どおり。

### フェーズ3（追加13）

- D02（完了）: `SearchFilters`（期間・人・プロジェクト・状態）と `MemoraModel+Search` を追加。`safeAreaInset` で結果の上に固定したチップから絞り込み、`解除` で戻す。タスクは期限・担当・元記録のプロジェクト・完了状態で絞り込み、記録固有の状態（処理中・要確認）では出さない。

### フェーズ3（追加12）

- D08: `MediaFiles.writePhoto(_:thumbnailMaxSide:)` が元画像とサムネイル（派生名 `<name>.thumb.jpg`）を書く。`photoThumbnailData` は無ければ元画像へフォールバック。`deletePhoto` は両方を削除、バックアップは `photoFiles(for:)` でサムネイルも同梱。ジャーナルの拡大表示は元画像、一覧はサムネイルを読む。

### フェーズ3（追加11）

- B12: 再生中のNow Playing情報を実体に合わせて公開（記録名、経過時間、長さ、速度）。`MPRemoteCommandCenter` で再生・一時停止・シークを操作可能にし、停止時に情報とターゲットを消去。名前が空のときだけ「無題の記録」。

### フェーズ3（追加10）

- E01（一部）: `RootTabView` が下部コントロールの高さを計測して `MemoraModel.bottomControlsHeight` に反映し、`bottomContentClearance`（高さ＋16）を各主要画面が使うように統一。ジャーナルの固定184ptを撤去。
- E05: 未連動だったアニメーション（AllMeetingsの一覧更新、Searchの追従と結果、写真追加、タスク完了）をReduce Motionに連動。

### フェーズ2の残り

- 写真（`Meeting.photoData`）のファイル参照化、A09（ごみ箱と復元）、
  B01〜B04（録音状態・AudioSession所有・割り込み・下書き保存）、バックアップ
  （バージョン付き書き出しと復元、非空時は上書きしない）、サービスの分離（F07）。

### 改善指示書（4回目）: 保存・復元（S01〜S04）

- **S01（実装済み・未検証）**: 下書きは1バイトの形式マーカー付きUTF-8で保存し、
  同じ規則で読む。旧ビルドのJSON文字列は明示的に一度だけ復号する。UserDefaults
  からの移行マーカーは `LocalStore` に読み書きし、本体と同一トランザクションで
  保存する（削除後に旧データが再取込されない）。`RecordStore` に
  `saveData`／`saveDataNow`、`DraftStore.saveAndWait` を追加。自己チェックは
  改行・引用符・日本語・空文字の往復、旧形式の復号、移行→削除→再読込、移行失敗の
  再試行を検証。
- **S02（実装済み・未検証）**: `LocalStore.applyBatch`／`RecordStore.commitNow`／
  `commitAsync` で「書込み＋削除」を1トランザクションにした。録音終了・音声なし
  メモの復旧・インライン編集は、本体保存の成功後にのみ下書きを消す。編集確定
  （`updateMeetingNotes`／`updateMeetingSummary`）は async・成否付きにした。
  録音下書きは記録になるIDを持ち、復旧は同じIDの記録があれば重複生成しない。
  自己チェックは一括コミットと失敗時（下書き・既存文書が不変）を検証。
- **S03（実装済み・未検証）**: 全ドキュメント読込後に保護状態を決める（AI履歴・
  録音下書きの読込失敗も反映）。保護中は保存だけでなく削除・期限切れ整理・復元も
  停止。ゴミ箱の移動・復元は「変更後の配列を組み立て→一括書込み→成功後に反映」。
  完全削除は削除待ち情報を持ち、DB確定後にのみファイルを消す（失敗は次回復試）。
  写真の削除も記録の確定後に行う。
- **S04（実装済み・未検証）**: 復元は同名メディアを上書きせず衝突エラーにし、
  ロールバックは当該復元が新規作成したファイルだけに限定。音声・写真を種類別に
  検証・重複排除し、フォルダ・シンボリックリンクを拒否。`Meeting` のdecodeは
  ファイルを書かず、旧インライン写真は読込後に明示的に書き出す。音声参照は生の
  保存値で検証する（`rawAudioReference`）。復元は保護中・録音中・下書き／ごみ箱／
  実AI履歴があるとき拒否する。自己チェックは種類衝突・シンボリックリンク・
  フォルダ・正常パッケージを検証。

### 改善指示書（4回目）: 音声・AI・操作性（U01〜U04）

- **U01（一部 実装済み・未検証）**: `AudioSessionCoordinator` は実行ごとの
  **トークン**で使用権を発行し、そのトークンだけが解放できる。録音は開始の全失敗
  経路で返却し、停止も自分のトークンでのみ終了。録音開始のトークンは`resume`で
  更新。音声入力は**実行ID**で権限待ち・旧コールバック・連打・画面終了を制御し、
  自分のトークンだけを解放。再生のリモート操作は一度だけ登録し、自分の登録
  トークンだけを解除。自己チェックはトークンAPIに更新。録音開始は先行する
  再生・音声入力の停止完了を待つ（R5で追加。`registerStopper`）。
- **U02（実装済み・未検証）**: スコープ変更は新しいチャットへ切替（保存済み履歴は
  残す）。全体スコープは記録に紐づかない未完了タスクも渡す（`openTasks(in: .all…)`）。
  非対応添付だけの質問は `.attachmentNotAnalysed` で回答せず説明する。エラー・
  キャンセル後も回答中状態を残さない（所有リクエストだけが解除）。資料の表示は
  「根拠」ではなく「AIに渡した参考資料」に統一。自己チェックはタスク範囲を検証。
- **U03（実装済み・未検証）**: 書き出し失敗は実際のエラー（欠落・アクセス・容量）を
  表示。フォルダ選択キャンセルはアラートにしない。書き出し・復元はメインアクター外
  で実行し、処理中オーバーレイとボタン無効化で重複操作を防止。成功表示は媒体とDBの
  確定後のみ。共有完了／キャンセル後に一時バックアップを削除（共有中は削除しない）。
- **U04（一部 実装済み・未検証）**: 添付は読込量にも上限（テキスト512KB・PDF 50MB）
  を設け、全量読込→切詰めをやめた。自己チェックは1MB超の日本語テキストが切詰め
  られることを検証。**未実施**: MainActorからの同期キュー待ちの非同期化（全保存
  経路）、JSON化のオフメイン化、100件／1,000件の実機計測。**性能改善率は書かない**。
- **T03（実装済み・未検証）**: 文字起こしの収集Taskは全経路で終了し、解析セッション
  は失敗・キャンセル時に `cancelAndFinishNow()` で閉じる。結果収集後に親の
  キャンセルを検知したら `cancelled` を返し部分適用しない。

### チームプラン（今回）

- `PlanTier`（個人／チーム）を追加。`MemoraModel.planTier`（`memoraPlanTier`）として
  保存し、`hasTeamPlan` がチーム機能のゲートになる。`choosePlan(_:)` はプランと
  `isSubscribed` を同時に更新する。**課金は未接続**で、プラン画面は「購入は準備中。
  いまは端末の設定として切り替える」と明記し、購入の成功を装わない。
- `PaywallView` は個人／チームの切り替え、ティアごとの特典、現在のプラン表示、
  「購入を復元」の未接続案内（DEBUGでは無料に戻す）を持つ。
- 設定の「プラン」に現在のティアと「チーム共有」を表示。未加入時は「チームプランで
  利用可」とロックを出し、プラン画面へつなぐ。
- チーム共有（クラウド・リアルタイム）: `CloudSharingService`（CloudKit）が
  **プロジェクト単位と会議単位の両方**を共有する。所有者がスナップショット
  （`TeamShareSnapshot`）を private DB に保存し `CKShare` を発行、システムの共有
  シート（`CloudShareSheet`）で招待する。参加者は `CKSharingSupported` 経由で
  `MemoraAppDelegate` が受け取り、shared DB を照会して `TeamSharesView` に一覧表示。
  変更は `CKQuerySubscription`（サイレントpush）＋前面復帰時の再読込で反映する。
  設定の「チームで共有されたもの」から確認できる。
- 共有は**読み取り専用スナップショット**で、ローカルの編集可能ストアへのマージ、
  メンバー管理、音声/写真の同期、競合解決は**未実装**。iCloudコンテナと
  entitlement、およびiCloudサインインが無い場合は、その旨を表示して動作しない。
- **状況（今回は保留）**: コードは実装済みだが、実機稼働は **Apple Developer Program
  （年額）のアカウント接続＋iCloudコンテナ/entitlement** を待つ。今回の判断では
  プロビジョニングは行わない。接続後にバンドルID割り当て・コンテナ作成・スキーマ
  配備・実機確認を行う。
- 手動のパッケージ書き出し `makeTeamSharePackage(meetingIDs:)` も残している
  （音声・写真・タスク・ジャーナルを含む。AI履歴・設定は含まない。復元は記録が
  空の端末のみ）。

### ファイル画面の複数選択と再生UI（今回）

- ファイルカード左スワイプの「共有」を「選択」に変更。選択モードではカードのタップで
  複数選択でき、下部のガラスバーから共有・プロジェクトへ移動・削除をまとめて行う。
  カードは選択状態を枠とチェックで示し、一括削除は確認ダイアログを出してごみ箱へ移す。
  一括操作は `MemoraModel.deleteMeetings`／`moveMeetings` で1回の書込みにまとめた。
- 会議詳細の再生を音楽アプリ風に刷新。アートワーク（再生中は波形が脈動）、タイトルと
  日時、経過と残りのスクラバー、Liquid Glassの戻る15秒／再生／進む15秒、速度メニューを
  ガラスカプセルで構成（`MemoraGlassContainer`＋`memoraGlass`、iOS 18ではmaterialへ後退）。

### 改善指示書（4回目）追補: 残課題の修正（R1〜R5）

- **R1 旧写真の移行（実装済み・未検証）**: `materializeLegacyPhotos()` は全写真の
  書込みが成功したときだけファイル名を採用し、1枚でも失敗したら書いた分を削除して
  元データを保持する（`false` を返す）。`Meeting.encode` は未移行のバイト列を
  `photoData` として保存し、保存の途中で失われない。起動時は失敗を
  `loadFailureMessage` で通知し、バックアップ書き出しは未移行の記録があると
  `inlineMediaUnsupported` で失敗する（復元できないパッケージを作らない）。
  自己チェック「Legacy photo retention」で往復保持と移行を検証。
- **R2 録音の保存失敗（実装済み・未検証）**: `stopCapture` は保存できなかった場合に
  成功経路へ進まず、録音情報・下書き・記録を保持し `hasUnsavedRecording` を立てる。
  `retrySavingRecording()` で再保存でき、解決するまで `startCapture` は新しい録音を
  開始しない（録音タップ時は先に再保存を試みる）。専用アラートから再試行できる。
- **R3 編集終了時の下書き（実装済み・未検証）**: 編集終了時に最新内容を
  `DraftStore.saveAndWait` で保存してから本体保存を試みる。`draftSessionID` を持ち、
  非同期の確定完了では「その編集セッションの下書き」だけを削除する（新しい編集が
  始まっていれば消さない）。デバウンス保存もセッション一致時のみ実行。
- **R4 復元の排他（実装済み・未検証）**: `isRestoring` でモデル側を排他し、
  復元中は録音開始・メモ追加を拒否。ファイル準備後、確定直前に `isEmpty` を
  再確認し、追加があれば配置したファイルを撤回して失敗させる。
- **R5 録音開始の停止待ち（実装済み・未検証）**: `AudioSessionCoordinator` に
  停止ハンドラ登録（`registerStopper`）を追加。`beginRecording()` は再生・音声入力の
  停止を待ってから録音へセッションを渡す。`resume` は `takeRecordingSession()` を使う。
  自己チェック「Recording stop order」で停止が取得より先であることを検証。
## 2026-10-14 次世代AI: スコープ付き読み取り

クラウド会話ループを共通化し、project/recordの検索・資料読取・関連タスクを
閉じた範囲で接続。既存履歴・引用・保存形式、GlassとFABは維持。長い記録の
末尾検索で見つかった不具合を修正。21 hostスイート、Simulatorの自己チェック、
Bitrig build成功。実BYOKの往復・権限変更・停止、承認付き変更、永続実行履歴／
再開は未確認または未実装。現況・証拠・残課題は[NEXT_GENERATION_AI.md](NEXT_GENERATION_AI.md)。

## 2026-10-17 e2e（シミュレータUIテスト）

`tester-army/e2e`（Apache-2.0）を開発用ツールとして追加した。アプリ本体・
Project.json は変更していない。設定は `e2e.config.ts`、テストは `tests/`。

- 対象: iOS シミュレータ（`mobile({ platform: 'ios', device: 'iPhone 18 Pro Max' })`）。
  `device` を指定しないと接続中の実機（Ken's iPhone）を掴むため、必ず指定する。
- アプリ: `app.bundleId` は Bitrig 生成の `app.bitrig.new.811eee03-…`、`appPath` は
  Debug の `Memora.app`。各テストの先頭で `device.installApp()` を呼ぶ。
- モデル: agent ステップは `@ai-sdk/deepseek` の `deepseek-chat`。`DEEPSEEK_API_KEY` は
  環境変数からのみ読み、リポジトリには保存しない。
- 実行: `E2E_TELEMETRY_DISABLED=1 npx e2e run`（テレメトリーは無効化）。
- 検証済み（`tests/memora.e2e.ts`、9件すべて成功・モデル呼び出しなし）:
  起動表示 / タブ切替（ジャーナル・ライブラリ・Ask AI）/ サイドメニューの主要導線 /
  設定表示 / 記録を追加のシート / タスク一覧 / 構造化回答の比較表とRow /
  構造化回答のストリーミング再生 / 根拠一覧と進捗の表示。
- 方針: 深い画面（設定 › プロトタイプ › 各例）へは `screen.swipe` でスクロールしながら
  ロケーターで辿る。**モデルを使わない決定的なテスト**にしてあり、キーなしで動く。
  agent（モデル）経由のテストは `e2e.config.ts` に用意済みで、必要時に追加できる。
- 制約: VoiceOverの読み上げ・日本語IME・実機のFPS/メモリは対象外。実プロバイダーの
  ストリーミングE2Eは別途実キーが必要。
- 注意: 共有された `DEEPSEEK_API_KEY` は無効化・再発行すること。
