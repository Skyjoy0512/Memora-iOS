# CIの緑表示と追加スライド検査の失敗

2026-10-29。開始main: `e6e53f070dbaaa174825b2caa60ee2067a969a3c`。
会社装飾色の実装後、[Actions run 40779370002](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40779370002)はsuccessだったが、
ダウンロードした追加検査の実ログに`PresentationRevisionChecks.swift:89: Precondition failed`があった。
**このrunの緑表示を、追加検査の合格とは扱わない。** 原本やUIの問題に読み替えず、検査と失敗伝播を修正した。

## 証拠と原因

- [Actionsがsuccessを返した記録](ci-failure/checks/ci-reported-green.json)と、[実際の失敗ログ](ci-failure/checks/e6e53f0-presentation-failed.log)を両方保存した。
- 既存6スイートは実ログで6/6成功していた。失敗したのは、その後の独立した追加スライド検査。
- 該当stepはshell未指定で、`bash ... | tee ...`がproducerの失敗を伝えていなかった。
  [GitHubの定義](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsshell)では、
  未指定の`bash -e`と、明示した`bash --noprofile --norc -eo pipefail`は異なる。
- 該当テストは、本番の300ms周期の権限監視が固定350ms待機までに完了すると仮定していた。
  CIで失効後の状態確認が間に合わなかった。OSのtimer配送が350ms以内に終わる保証を成功条件にしない。

## 修正

- 追加検査stepに`shell: bash`を明示。4本のログ付きpipelineは維持し、producer/loggerいずれかが失敗したらstepを失敗させる。
- 同じstepの先頭に、実際のworkflow設定と失敗伝播の回帰テストを追加した。新規依存はない。
- 修正案生成の応答をchecked continuationで保持し、本番の権限監視が停止・失敗状態を発行するまで待つ。
  その後に許可を戻して古い応答を解放し、提案が復活しないことを検査する。
- 取消後の古い応答も、新しい失敗状態を作ってから明示的に解放する。固定80ms/500msの競合に頼らない。
- 状態待ちには単調時計の5秒の失敗期限がある。判定を削除せず、失効・重複拒否・取消・置換後の不変性を維持する。

`App/PresentationRevisionSession.swift`の本番処理、監視周期、権限/取消条件は変更していない。
変更は`.github/workflows/quality.yml`、`tools/checks/PresentationRevisionChecks.swift`、
新規`tools/checks/test_ci_failure_propagation.py`と、報告・ログのみ。
standard-projectの指示を確認し、Project.json/target/Info.plist/Bundle ID/権限/リソース設定は変更しなかった。

## 検証

| 検査 | 結果と範囲 |
| --- | --- |
| pipeline producer失敗 | exit 17を保持、ログ保持、後続処理なし |
| logger失敗 | 非zero、後続処理なし |
| 正常pipeline | ログ保持、後続へ継続 |
| 実workflow設定 | 該当stepの明示bashと4本の検査が維持されていることを確認 |
| スライド修正/描画/出力 | 65/65成功、独立ZIP/XML/参照/編集可能図形/日本語/出典/PDF検査も成功 |
| 反復 | 実行体を別出力先で5回実行し、すべて成功。独立Python package validatorの反復ではない |
| 追加step全体 | GitHubと同じ明示bash引数で、標準65型/修正権限/inline links/OSSの4本がすべて成功 |
| Debug preview | 成功、iOSプレビュー更新。既存11警告 |
| Release | 成功、既存11警告。iOS 27.1 SDK/Simulator、deployment iOS 26 |

[pipeline 4件](ci-failure/checks/pipeline-unit.log) / [標準65型と独立package検査](ci-failure/checks/presentation.log) /
[反復1](ci-failure/checks/repeat-1.log) / [2](ci-failure/checks/repeat-2.log) / [3](ci-failure/checks/repeat-3.log) /
[4](ci-failure/checks/repeat-4.log) / [5](ci-failure/checks/repeat-5.log) / [Debug](ci-failure/checks/debug.log)。
[追加step全体](ci-failure/checks/whole-step.log) / [修正権限](ci-failure/checks/presentation-access.log) /
[inline links](ci-failure/checks/inline-links.log) / [OSS](ci-failure/checks/oss.log) / [Release](ci-failure/checks/release.log)。

新しいCIの成否は、修正後HEADのActionsと実ログで別途確認する。旧runのsuccessを流用しない。
テストの削除/skip、主張・数値・出典の制約緩和、失敗を握りつぶす変更はない。

## 継続する境界

実AI/Office/実機や全型の最終描画は未検証。会社PDFの原本ページ変換、一般会社書式、
Quick Lookの色差、ローカルPowerPointのopen timeoutは[装飾色レポート](COMPANY_DECORATION_COLOR.md)のまま。
最終完成数は **0 / 65** を維持する。今回も新規費用/サービス/有料APIは追加しない。

```sh
python3 -B tools/checks/test_ci_failure_propagation.py
MEMORA_CHECK_ROOT=<外部SSD検査先> bash tools/checks/run-presentation-checks.sh
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
```
