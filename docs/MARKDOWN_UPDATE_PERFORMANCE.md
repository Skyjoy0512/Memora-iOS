# Markdown更新の測定と重複分割の除去

2026-10-16。基準は`1cb1d8d62c33f997f380a5b99d34ed13b4fda3bb`。既存のPERFORMANCE_OPTIMIZATION.md、MarkdownStreamingBenchmark、増分parser、native UI抽出、inline描画cache、Homeの集計を確認した。

## 変更と採用判断

MarkdownBlockParser.sourcedBlocksは、最初のcomponentsで行を解析した後、EOFの行番号を知るためだけに同じ全文を再びcomponentsへ渡していた。未確定のコード/表/リスト/段落ではこの余分な分割が公開ごとに起きる。まず一時ファイル内の候補で比較し、長いブロックで処理時間の短縮を確認したため、本番では既存loopのindexから行数を保持する3行の変更だけを採用した。

Markdownの文法・block構成・編集用source range・parserのcache・既存IncrementalMarkdownの確定境界は維持する。新しいState/cache/タイマー/描画計測の書込は追加しない。NativeAIInterfaceの全受信/検証/承認、100msのstream公開制御、コピー・選択・編集、Liquid Glass/FAB/Hero/Navigation/composer、SQLite/backup/権限/BYOKは変更しない。

Home等のUI再構築、追加のderived cache、equatable指定、stream更新頻度の変更、未確定Markdownの描画省略は採用していない。画面全体のtraceがない状態で、既存の最適化を置き換える根拠がないため。

## 測定条件

- Apple Silicon arm64、macOS 27.0.1、Apple Swift 6.4、`swiftc -O`、ContinuousClock。
- 同じbinary内にGitから取り出した基準parser/incrementalと現在の実装を別名でコンパイル。各fixtureで先行する実装を交互に替え、warmup 2回を除く21回。中央値は11番目、p95は20番目。
- 架空の日本語5fixture。80 Unicode scalarごとの同じ全文snapshotを事前に生成し、stream更新と最後のcompletionを測る。入力生成と正しさの比較は時間に含めない。実装が公開するblocksの取得は含める。
- 変更前後の最終SourcedMarkdownBlock（本文/構造/行範囲）を完全比較。各実行の最終増分blocksも比較する。
- 本番codeの最終測定中はBitrigビルドを開始していない。OS/他プロセスの変動は残る。信頼区間は算出していない。
- これはhostの解析CPU処理時間。メインスレッド占有、SwiftUI body/レイアウト/描画、GPU、frame、ネットワーク、初回token、iPhone Releaseの時間ではない。80 scalarは測定用のchunkであり、本番公開頻度を変えるものではない。

再実行:

```sh
python3 tools/checks/run-markdown-update-benchmark.py --baseline 1cb1d8d --output docs/MARKDOWN_UPDATE_BENCHMARK.json
```

生の集計値・compiler/OS・baseline・現在のsource SHA-256は[MARKDOWN_UPDATE_BENCHMARK.json](MARKDOWN_UPDATE_BENCHMARK.json)。一時的なソース/binaryは専用TemporaryDirectoryへ隔離し、終了時に除去する。実API・キー・ユーザー記録は使わない。

## 結果

以下は1回の回答の**全更新＋completionの合計**。単一frame/単一更新の時間ではない。

| fixture | bytes / 更新数 | 変更前 中央値 / p95 ms | 変更後 中央値 / p95 ms |
|---|---:|---:|---:|
| 短い段落と見出し | 18,130 / 92 | 2.386 / 3.454 | 2.281 / 3.550 |
| 空行のない箇条書き | 31,890 / 162 | 42.184 / 44.852 | 35.069 / 36.898 |
| コードblock | 23,903 / 174 | 25.453 / 25.684 | 16.761 / 16.873 |
| 表 | 12,224 / 78 | 17.977 / 18.343 | 16.194 / 16.567 |
| 長い1段落 | 29,400 / 123 | 8.965 / 9.055 | 6.076 / 6.136 |

コードfixtureの最大更新時間の中央値は0.297→0.197ms。短い段落fixtureの差は小さく、p95は改善していない。全caseが速くなったとは扱わない。parsedBytesは同じであり、削減したのはparse内部の重複分割。計測結果からSwiftUIの再描画回数、メモリ削減量、操作待ち時間やFPSの改善率を推定しない。

## 回帰とビルド

- `run-motion-loading-checks.sh`: 成功。既存の1/7/37 scalarごとの増分/完成一致、fence/table/link/Unicode/置換/再表示に加え、EOF・末尾改行・CRLF・未完fence・表・箇条書きの編集用行範囲13caseを検証。
- `run-next-generation-checks.sh`: 成功。既存scope/privacy/provenance、会話codec、agent/registry/MCP、stream、NativeAIInterface、root navigation等。
- `bitrig preview -platform iOS`: Debug成功、プレビュー更新。log `2026-10-16T18-05-20-c73f5431.log`。
- `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`: 成功。log `2026-10-16T18-06-30-077ca3d2.log`。
- 両ビルドの警告は既存Share ExtensionのAppIntents metadata抽出省略1件。logは当該projectのBitrig Builds/logs内。
- `git diff --check`: 成功。

DebugプレビューのiPhone 18 Pro Maxで、Settings → プロトタイプ → 状態と復旧 → Loading・本文表示を確認を使用した。架空SSEからの本文生成後、AXに見出し・箇条書き・表・コード・12段落があることを確認。完成した日本語段落はscreenshotでも確認した。開始直後のAX読取は一度失敗したが、次の読取では完成本文を取得できた。これはcrashの証拠でも、全frameが滑らかだったという証拠でもない。

## 主要画面と実機の未測定範囲

最新プレビューのMemora PIDを特定し、`xctrace record --template 'Time Profiler' --attach <pid> --time-limit 10s --no-prompt`を試したが、exit 21 / `Cannot find process for provided pid`でtraceを取得できなかった。失敗した一時traceは除去した。接続エラーから原因を推測したり、別の実行環境の値を当該appの値として使ったりしない。

起動/Home完了、タブ・議事録初回表示、Animation Hitches、スクロールframe drop、メインスレッド占有、SwiftUI body回数、peak memory、初回AI本文、Skeleton頻度の変更前後は未測定。過去のPerformanceLogは同一appVersionの別試行が混在するため比較に流用しない。実機Releaseと主要画面のtraceが次の課題であり、このhost benchmarkで代用しない。
