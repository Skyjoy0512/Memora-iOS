# 標準シミュレーターのTime Profiler取得

2026-10-16。アプリコードは`0fdf1c3`。アプリのUI・モデル・保存・権限・課金処理はこの追加で変更していない。取得/解析ツールと検証結果を追加した。

## 取得経路

以前のBitrig内蔵シミュレーターのPID attachでは`Cannot find process for provided pid`となっていた。今回、インストール済みの標準CoreSimulator iOS 27.0ランタイムを確認し、Memoraのdata containerがないiPhone 18 Pro Maxで、Bitrigが作成した既存Release成果物を起動した。初回案内をスキップするとHome/Library/Ask AIの空状態へ移動できた。実記録の追加/削除、AIへの質問、録音、外部サービス接続はしていない。

`xctrace --device <標準simulator UDID> --attach <そのsimulatorのPID>`で取得できた。process name指定の初回試行は失敗したため、最終toolは`simctl spawn <UDID> launchctl list`から当該bundleのPIDだけを選ぶ。ホスト側の`pgrep Memora`はBitrig内蔵版と標準版の両方に一致するため、対象の特定に使わない。

この経路の成功は、内蔵シミュレーターで失敗した原因の確定を意味しない。ETTraceの追加リンク、Node、外部依存、project設定、Apple Developer設定、権限の変更は行っていない。

## 正確な成果物

- ビルド: Bitrig Release、`2026-10-16T18-06-30-077ca3d2.log`で成功した成果物を再利用。
- 対象: 標準iPhone 18 Pro Max Simulator、iOS 27.0 (24A434)。ホストmacOS 27.0.1、Instruments 27.1 (27A9275)。iPhone実機の値ではない。
- arm64 app UUID: `802E7CEB-5E51-39ED-9884-0DA761F6CC7F`。trace内のMemora imageと`dwarfdump --uuid`の実行ファイルが一致。
- 実行ファイルはuniversal。取得toolはインストール済みappと指定したBitrig成果物のUUID/architecture集合も照合する。
- 初回の10秒静止画面captureはtime-profile tableが0行だったため、性能評価に使っていない。recordコマンドの成功だけで有効な性能測定としない。

## 観測結果

Home → Library → Ask AIを操作し、Homeへ戻した。2回目は追加したcapture toolで取得からexport/集計まで実行した。2回とも要求した記録窓は20秒。初回には初めて開く画面の処理が含まれ、手動操作の間隔も厳密には同じではない。変更前後の比較や改善率には使わない。

| 指標 | 初回操作 | 同じビルドの追試 |
|---|---:|---:|
| time-profile sample数 | 1,493 | 915 |
| 全threadのsample weight合計 | 1,493ms | 915ms |
| main threadのsample weight | 948ms | 805ms |
| 曖昧なapp symbolを含むsample weight | 8ms | 3ms |
| backtraceなしのsample weight | 1ms | 1ms |

sample weightは統計的な重みであり、タブ遷移の応答時間、厳密なCPU占有時間、frame時間ではない。thread間の和、inclusiveな関数の重み、20秒の記録窓は異なる量で、inclusive値を関数間で足し合わせない。sampleの最初から最後までのspanも記録窓全体ではない。

初回leafにはSwift protocol適合の確認が374ms相当含まれた。app内のLibraryView.body/UpcomingMeetingStore.refresh等の名前も確認できたが、記録は空データ/初回表示の影響を含む。appの`main`/`MemoraApp.$main`の大きなinclusive値は、配下のUI処理を含む入口であり、関数本体のボトルネックとは扱わない。追試のapp側にはicon render等もあるが、単発の小さなsampleだけを根拠に、既存のnative UIやcacheを作り替えない。

`<deduplicated_symbol>`は特定のapp関数へ割り当てられず、1 sampleのbacktraceも欠けるため、両方とも**部分的なシンボル解決**として報告する。名前が取れた値だけを一覧へ出し、完全なソース別帰属とは主張しない。Time Profilerは「input source不明のtableが1つ」という警告も出した。sample取得はできているが、この警告から他の計測表の完全性を推測しない。

集計: [SIMULATOR_TAB_PROFILE.json](SIMULATOR_TAB_PROFILE.json)、[SIMULATOR_TAB_PROFILE_REPEAT.json](SIMULATOR_TAB_PROFILE_REPEAT.json)。これらは関数名/UUID/集計だけで、host名・個人記録・API引数・認証情報・生のstack address/pathを含めない。

raw trace/XML/logはGitへ追加せず、実体を確認したWorkspaceSSD（DevSSDの実体）に保持:

- 初回操作: `/Volumes/WorkspaceSSD/Development/Temp/memora-tab-switch-profile-ua2ald6w/`
- tool追試: `/Volumes/WorkspaceSSD/Development/Temp/memora-tab-profile-runner-20261016-check1/`

## 再実行

Bitrigで対象Releaseを作成/起動し、実データのない標準シミュレーターで、Homeの空状態から始める。既存app/dataの消去は不要で、toolにも消去機能はない。

```sh
python3 -B tools/checks/capture-simulator-profile.py \
  --simulator <標準シミュレーターのUDID> \
  --app <bitrigが出力したMemora.app> \
  --configuration Release \
  --output-dir <既存の親ディレクトリ内の新規フォルダ> \
  --seconds 20
```

Recordingの表示後に同じタブ操作を行う。toolは指定されたboot済みiOS Simulatorだけを対象とし、appをbuild/boot/launch/resetしない。bundle/PID/installed UUIDを確認し、新規folderへだけ出力する。raw artifactのGit混入を防ぐため、repo内の出力先は拒否する。record/exportの失敗やempty/mismatchを成功扱いしない。stdoutの完了結果とrecord.logの警告を両方確認する。

既存exportの再集計:

```sh
python3 -B tools/checks/simulator_profile_summary.py <profile.xml> \
  --expected-uuid 802E7CEB-5E51-39ED-9884-0DA761F6CC7F
```

schema/列順、interned ID/ref、UUID、一意のapp process、非負で有効なweightを検証する。再帰frameはsample内で一度だけ加算する。empty、欠けた参照、循環、異なるrunの混在、UUID不一致は拒否し、backtrace欠落や曖昧なsymbolは明示する。初回取得の0行exportがこのcheckで拒否されることも確認した。

## 検証と未検証

`test_simulator_profile_summary.py`の5 test群が成功。参照解決/再帰の重複加算防止、empty/schema、UUID/process不一致、欠落/循環/重複ID、負/ゼロ/過大weight、部分的なsymbol/backtraceを隔離XMLで検証。実capture toolもインストール照合から20秒記録/export/集計まで成功した。Python標準ライブラリのみ。

`run-motion-loading-checks.sh`は新checkを含め成功。`bitrig preview -platform iOS`も成功し、現在のBitrigプレビューを更新した（log `2026-10-16T18-25-00-c50bdfc1.log`、既存Share Extensionのmetadata抽出省略warning 1件）。Releaseは上記の既存成果物を使用しており、新しいRelease buildの測定とは表示しない。`git diff --check`も成功。検証終了後、今回bootした標準simulatorを元のShutdownへ戻し、今回変更したXcodeBuildMCPの一時defaultsも元の未設定へ戻した。traceと隔離app containerは保持し、既存データを消去していない。

主要画面の操作は空状態での到達を確認した範囲。大量ファイル、議事録詳細、生成回答、スクロール、キーボード、Dynamic Type等の網羅的なUI検証ではない。起動/Homeの操作可能になるまでの時間、個々のタブ遷移時間、Animation Hitches、FPS、SwiftUI body回数、メインスレッドの正確な占有時間、peak memory、iPhone実機Release、before/after改善率は引き続き未測定。次は同じ環境で、固定した架空データと明示的な操作区間を使う描画計測を優先する。

## 描画計測の追加確認と環境の制約（2026-10-16）

基準`cc595a1`、開始時main/クリーン。同じBitrig Release成果物（arm64 UUIDは上記と同じ）を、前回の隔離された空の標準iOS 27.0 Simulatorへ起動した。アプリのコード、Project.json、保存データ、権限、課金処理は変更していない。フレームの計測可否を先に確認し、以下を観測した。

| 取得構成 | 実際の結果 | 性能評価への扱い |
|---|---|---|
| Animation Hitches、20秒指定、初回 | exit 21、`Cannot find process for provided pid` | 取得失敗 |
| 同じdevice/PIDのTime Profiler、5秒 | exit 0、record完了。既存input-source warning | attach経路の対照確認だけ。静止画面で性能比較しない |
| Animation Hitches、20秒指定、再試行 | exit 2、`Hitches is not supported on this platform.` | platform非対応。exportもrun data欠落で失敗 |
| SwiftUIテンプレート、30秒指定 | exit 2、同じHitches非対応 | テンプレート内のHitchesで失敗。body計測成功ではない |
| Time Profiler + `--instrument SwiftUI`、30秒 | exit 0、`Trace file had no SwiftUI data` | record終了をbody/FPS/Hitchesの有効な測定としない |

最後の構成は、非対応のHitchesを含むテンプレートを避けてSwiftUI instrument単体を追加したもの。capture終了前に行った最初のexportは`Document Missing Template Error`で失敗した。recordプロセスの終了後にexportをやり直すとTOCは取得できたが、SwiftUI dataなしというwarningは解消しなかった。警告や空の表から「重いbodyなし」「フレーム落ちゼロ」とは結論しない。

各操作では、AXの最新snapshotからタブを特定し、Home → Library → Ask AI → Homeを2巡した。各tapの戻り値で選択状態を確認した。これは空状態での画面到達の確認であり、操作toolの往復時間（AX取得と待機を含む）をアプリの遷移時間へ換算しない。中間フレームの連続観測も、固定した架空本文の描画測定も未完了のまま。

ローカルで確認したInstruments 27.1の構成にはAnimation Hitches/SwiftUIテンプレートが列挙されていたが、列挙されることは選択したplatformでの動作保証ではなかった。Appleもhitchの現実的な評価には実機を推奨している（[Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)）。今回のエラーの原因を、すべてのSimulator/OSでの非対応へ一般化しない。

raw log/trace/TOCはGit外の`/Volumes/WorkspaceSSD/Development/Temp/memora-animation-hitches-bnzy3ztg/`へ保持した。失敗したtraceを集計JSONへ追加していない。次の描画計測は、実機Releaseとテスト専用データを使い、固定した操作区間で行う必要がある。この作業ではユーザーのiPhoneへのインストールや、実サービス/実記録の利用を行っていない。

### 取得toolの失敗時の検証

`capture-simulator-profile.py`はTime Profiler専用のまま維持した。タイムアウト時も途中のstdout/stderrを`record.log`へ残し、export/再試行/summary生成へ進まないようにした。`subprocess`のtimeout出力がtext指定でもbytesになり得るため、UTF-8の不正byteを置換して診断を保存する。

`test_simulator_profile_capture.py`の7 testで、実コマンドをすべてmockし、次を確認する。ユーザーのSimulatorやデータへ触れるテストではない。

- shutdown/未利用可能/異なるdevice、未起動/重複/停止済み/別bundleのjobではattachしない。
- 指定成果物とinstalled appのUUID不一致ではattachしない。
- repo内の出力と既存folderを拒否し、既存の内容を保持する。
- 明示的なdevice/PIDを使い、all-processesやlaunchへ拡大しない。
- record失敗/timeoutではlogを保持し、export/自動再試行/summary生成をしない。
- recordがexit 0でもexport失敗/空XMLなら測定成功にしない。

既存summary検証5 testと合わせて12 test成功。motion-loading runnerへ両方を組み込んだ。アプリのUI/モデルへの追加の性能最適化は、この無効な描画測定を根拠に実施していない。

最終検証: `run-motion-loading-checks.sh`全件成功（loader/scroll/Markdown/catalog/budget/承認取消/workspace世代を含む）。`bitrig preview -platform iOS`成功、log `2026-10-16T18-37-07-45157243.log`。既存Share ExtensionのAppIntents metadata extraction省略warning 1件。新しいRelease buildは作成せず、上記の既存Releaseで取得した。`git diff --check`成功。標準Simulatorは元のShutdownへ戻し、変更した一時defaultsを未設定へ戻した。隔離containerの削除や初期化はしていない。
