# 会社プレビューの結果待ち・失効検査

2026-10-29。開始main: `d60525b7c5668c551727ba84d91bab18166f2b08`。
前フェーズの[追加ページプレビュー/PDF](COMPANY_PREVIEW.md)で未実施としていた、生成結果待ちの決定的な中断検査を追加した。
UI、保存形式、描画、会社原本、既存資料は変更しない。65型の最終完成数は **0 / 65** を維持する。

## 実装

- `loadCompanyPresentationPreview`の準備処理を、既定では同じ本番のファイル読込/生成処理へ渡すよう分離した。
- 準備前・detached worker開始時にも取消を検査し、開始前に取り消された要求からファイル読込を始めない。
- worker後の取消・本文/書式/workspace/保護/復元の再検査を維持した。結果を返す直前の再検査までが本番コード。
- テスト専用actorが実PPTXの読込・実プレビュー生成の完了後に結果を保持する。到達を待って状態を変更し、その後に解放する。経過時間やsleepに依存しない。
- テストは本番の準備処理を呼ぶ。成功sceneをダミーへ置換して結果待ちを検証したことにはしない。

## 決定的な12ケース

| 結果待ち中の条件 | 期待する結果 |
| --- | --- |
| 変更なし | 同じページscene/原本ページ数を返す |
| スライド本文編集 | staleで拒否 |
| 文書削除 | staleで拒否 |
| 会社書式version更新 | staleで拒否 |
| 会社書式analysis更新 | staleで拒否 |
| 会社書式削除 | staleで拒否 |
| 別workspaceへ移動 | staleで拒否 |
| workspace往復と世代更新 | staleで拒否 |
| 世代だけ更新 | staleで拒否 |
| 復元開始 | staleで拒否 |
| ストア保護 | staleで拒否 |
| Task取消 | CancellationErrorで拒否 |

全ケースで生の原本ファイルとSQLiteの文書保存バイトが変わらず、テストで変更したメモリ上の現在値も古い値へ戻らないことを検査する。
状態変更はこの検査ではメモリ上のfixtureに対して行い、実アプリでの編集保存・通知・共有E2Eとは区別する。

開始前の既存8失効条件は、準備処理が0回で、型付きstaleエラーになることまで厳密化した。
開始前取消も準備0回を確認する。準備エラーの伝播、原本欠落、旧形式の拒否も保持する。

## 結果とログ

| 検査 | 結果 | 実ログ |
| --- | --- | --- |
| 専用状態検査 | 12ケース、開始前失効/取消の準備0回、型付きエラー、不変性成功 | [専用検査](preview-interruption/checks/access-passed.log) |
| 既存6スイート | 6/6 Pass。新検査もnext-generation内で再実行成功 | [summary](preview-interruption/checks/summary.json)、同フォルダの6ログ |
| 会社プレビュー/PDF65型 | 65/65ホスト検査成功 | [next-generation](preview-interruption/checks/next-generation.log) |
| Debug preview | 成功、iOSプレビュー更新。既存11警告 | [Debug](preview-interruption/checks/preview.log) |
| Release | 成功、既存11警告 | [Release](preview-interruption/checks/release.log) |

ビルドはiOS 27.1 SDK/iOS 26 deployment、Simulator対象。実機での確認ではない。
初回の専用検査は、コンパイル中にテストソースを修正したためcompilerの入力変更検出で失敗した。
ソースを固定した再実行は成功した。[失敗ログ](preview-interruption/checks/access-initial-failed.log)も残す。

前フェーズHEADの[GitHub Actions](https://github.com/Skyjoy0512/Memora-iOS/actions/runs/40695339401)は成功し、
ダウンロードしたhost-quality-resultsの6スイートと65型/状態検査の実ログを照合した。これは今回の変更後CIの代わりではない。

## 未実施・非対象

- OSプロセス終了、CPU計算やファイルIO自体の途中の強制中断、実機、UI→共有E2E。
- 全65型それぞれで中断する組合せ試験。12ケースは構造化b01 fixtureで行い、65型の描画/PDF検査は別経路。
- 外部からの原本ファイル置換に対する新たなハッシュ拘束や、任意の会社書式への対応。
- 原本込み会社PDF、Quick Lookの色差解消、Office/Keynoteでの最終描画、実AI選択/修正。
- CPU/メモリ/電池/速度のBefore/After測定。開始前取消の検査を、測定済み高速化とは報告しない。

新規依存、サービス、API呼出、固定費、Project.json変更なし。録音/文字起こし、既存資料/バックアップ、BYOK、認証/課金は維持する。

## 再現

```sh
bash tools/checks/run-artifact-operation-checks.sh --company-preview
bash tools/checks/run-quality-checks.sh --output-dir <未作成の外部SSD結果先>
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
```

状態検査は既存next-generation内で実行される。スイートを削除・skipする変更はしていない。
