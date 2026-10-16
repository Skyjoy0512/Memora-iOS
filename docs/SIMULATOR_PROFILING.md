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
