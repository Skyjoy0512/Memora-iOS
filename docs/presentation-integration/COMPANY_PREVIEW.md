# 会社書式の追加ページ・プレビューとPDF

2026-10-28。開始main: `1a609a859dcea5ba318873d6cdd3352407376cfa`。実装: `d829a6c`。
会社PPTXの**追加ページだけ**をネイティブ表示・PDF共有する経路を追加した。
原本ページ込みの会社PDFは未実装。全完成条件は **0 / 65** のまま。

## 実装完了

- 保存済み会社スライドの詳細に「追加ページを会社書式で確認」を追加。現在の保存済み本文/書式を明示的に開く。
- PPTXと同じ入力検査・空白レイアウト選択・会社フォント/配色役割を使う。実ファイルを再解析し、PPTX生成可能性も確認する。別レイアウトやMemora標準色へ黙ってフォールバックしない。
- マスター/レイアウトの単色・輪郭線なしの矩形/楕円装飾を元の順序で描画する。画像、文字装飾、輪郭線、透明度、回転/反転、グループ、複雑な図形等は省略せず拒否する。画像ロゴは未対応。
- 同じCoreGraphics/CoreText要素をCanvas/PDFへ渡す。文字は検索・選択可能、図表はベクトル。Office Chart/Excel編集機能とは異なる。
- 除外する原本ページ数を表示し、「PDF（追加分のみ）」で共有。PDFのタイトルメタデータ/一時ファイル名にも範囲を残す。原本込みのPDF変換は未対応と表示する。
- 文書/書式/workspace世代を固定し、worker前後と共有前に、同じ保存済み文書/書式、保護/復元、取消を検査。失効したプレビューは閉じる。読み取りだけなので履歴上限やSQLite書込失敗に結び付けない。
- 原本・既存PPTX・履歴・SQLiteは更新しない。PDFは共有用の一時ファイルで、共有終了時に片付ける。外部送信は利用者がシステム共有先を選ぶ場合だけ。AI/API/クラウド/依存/固定費の追加なし。

native-app-designの方針で既存SlideViewと標準の閉じる/共有、読み取り用DisclosureGroupを再利用した。
会社テーマと周辺UIのsemantic色を分離し、待機は短いshimmerだけにした。
[Appleのsheets](https://developer.apple.com/design/human-interface-guidelines/sheets)を参照。
録音、文字起こし、ジャーナル、保存形式、認証/購入、Project.jsonは変更していない。

## 実描画で見つけた色空間の問題

既存のPresentationDrawing.colorはGeneric RGB initializerを使っていた。
DrawingMLのsRGB指定値と同じ数値でもPDFの実画素が変わったため、明示的sRGBへ修正した。
標準/会社資料の共通描画へ適用するが、ブランドのhex値は変更していない。
[Generic RGB](https://developer.apple.com/documentation/coregraphics/cgcolor/init(red:green:blue:alpha:)) /
[sRGB](https://developer.apple.com/documentation/coregraphics/cgcolor/init(srgbred:green:blue:alpha:))を確認した。

b22の合成fixtureを960×540の明示的sRGB CGContextへ描画し、同じ座標を採取した結果:

| 対象 | 修正前PDF | 修正後PDF | Quick Look PPTX |
| --- | --- | --- | --- |
| マスターの緑矩形 | 0,108,99 | 0,90,80 | 0,90,80 |
| 緑の円 | 0,108,99 | 0,90,80 | 0,108,99 |
| 茶の円 | 148,68,0 | 128,51,0 | 148,68,0 |

指定色は緑 #005A50、茶 #803300。修正後PDFは指定値で描画できたが、
**Quick Lookの円/自由形状などには色差が残る**。全形状の実画像一致を合格にしない。
原因をQuick Lookだけに断定せず、Office/Keynote/実機での照合を残す。
[生測定](company-preview/checks/color-comparison.json) /
[修正前PDF](company-preview/b22-before-generic.pdf) /
[修正後PDF](company-preview/b22-after-srgb.pdf) /
[Quick Look](company-preview/renders/b22-quicklook.png)。

lumMod/lumOffはRGB各成分の加算ではなくHSLの明度へ順に適用し、緑の淡色 #ABFFF6等を検査した。
[Microsoftの説明](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.luminancemodulation?view=openxml-3.0.1)を参照。
生成要素の既知の変換だけを扱い、装飾自身の色変換はこの版では拒否する。

## 検証完了と境界

| 検査 | 結果 | 境界 |
| --- | --- | --- |
| 全65型 | 会社色/フォント、装飾、PDF日本語、原本除外、再生成scene一致 | 短い合成fixture。一般会社書式ではない |
| PDF実画素 | 65/65でマスター矩形が指定sRGB | Office全形状との画素一致ではない |
| 集約成果物 | PDFは追加65ページ、PPTXは原本1＋追加65ページ | 収録範囲は意図的に異なる |
| 独立パッケージ検査 | 65/65。XML/参照/編集可能図形/日本語/出典/原部品バイト | Office最終描画の代わりではない |
| 非対応装飾 | 輪郭不明、透明度、diamond、背景依存、文字、hidden、重複fillを拒否 | 拒否を一般書式対応の成功に数えない |
| 状態/権限 | 実ファイル/SQLite不変、本文/書式変更・削除、workspace往復、保護/復元、取消、原本欠落、legacy拒否 | 本番factory/worker/最終検査。OS通知やUI保存E2Eではない |
| 実画像 | 65組を生成、11比較シートを目視 | 色/フォント等の差が残る。全一致ではない |
| 既存6スイート | 全Pass | ローカルホスト。CIは同じHEADのActionsで別途照合 |
| Debug / Release | 両方成功、既存11警告 | iOS Simulator/iOS 27.1 SDK。実機ではない |
| Simulator | Light/Dark、最大文字、本文/ノート開示とスクロール | 保存しないDEBUG表示例、m04/m14/b24 |
| XCTest/XCUITest/SnapshotTesting | 未実施 | target/config追加なし |

状態の失効8条件はworker投入前の拒否を検証した。worker結果待ちの途中をgateで停止させる
決定的な中断テストや、OSプロセス終了は今回未実施。投入後の本番再検査を、そのテスト完了と混同しない。

既存6スイートを削除/skipせず、65型プレビューと状態検査をnext-generationへ追加した。
初回の専用テストではthrowをpreconditionへ直接渡す記述を修正した。
非DEBUGの状態検査からDEBUG限定fixtureを呼んでいた箇所は、本番の構造化入力へ置換した。
比較ツール単体のコンパイルには -parse-as-library を指定した。失敗を成功へ読み替えていない。

## 成果物・ログ

- [追加65ページPDF](company-preview/corporate-additions-65.pdf) / [原本＋65型PPTX](company-preview/corporate-catalog.pptx) / [架空の原本](company-preview/source.pptx)
- [65型個別検査](company-preview/checks/preview-handoff-checks.log) / [状態・権限](company-preview/checks/access-checks-final.log)
- [Debug](company-preview/checks/preview-verified.log) / [Release](company-preview/checks/release-verified.log)
- [6スイート](company-preview/checks/summary.json)と同フォルダの個別ログ
- 比較画像: [b01–b06](company-preview/renders/comparison-0.png)、[b07–b12](company-preview/renders/comparison-1.png)、[b13–b18](company-preview/renders/comparison-2.png)、[b19–b24](company-preview/renders/comparison-3.png)、[b25–b30](company-preview/renders/comparison-4.png)、[m01–m06](company-preview/renders/comparison-5.png)、[m07–m12](company-preview/renders/comparison-6.png)、[m13–m18](company-preview/renders/comparison-7.png)、[m19–m24](company-preview/renders/comparison-8.png)、[m25–m30](company-preview/renders/comparison-9.png)、[m31–m35](company-preview/renders/comparison-10.png)
- [差分の数値](company-preview/checks/render-comparison.json): 65組平均0.01170。自動合格基準ではない。既存ツールのblueOverlapRecallは緑/茶テーマの判定に使わない。
- Simulator: [Light](company-preview/screenshots/native-light.png) / [Dark](company-preview/screenshots/native-dark.png) / [本文開示](company-preview/screenshots/reading-light.png) / [最大文字・操作](company-preview/screenshots/accessibility-reading-dark.png) / [最大文字・本文](company-preview/screenshots/accessibility-text-dark.png)

Quick Look用コピーは検証専用に原本ページのpresentation-list entryだけを除外した。
追加ページ/マスター/テーマは元PPTXと同じ部品。納品用PPTXは原本込みのまま。
原本全ページの描画検証ではない。追加UIのため、同内容の実Simulator Before画像はない。
表示設定はLight/largeへ復元済み。VoiceOver実聴取、小型端末、実機、回転、低メモリは未検証。

## 未実装・次の課題

- 原本ページの忠実な描画と、原本込みの会社PDF。追加分PDFをその完成として報告しない。
- 画像ロゴ、一般プレースホルダー、任意寸法、表/チャート詳細書式、ページ番号/フッター等。既存の条件限定appendを維持する。
- 円/自由形状の色差、フォント/アンチエイリアス差のレンダラー別評価。全65型の最終完成は0/65。
- 実資料のプレビュー→PDFシステム共有E2E、実AI選択/修正、Office/Keynote/実機、snapshot自動回帰。
- プレビューはPPTX生成可能性も検査するため一時メモリを使う。CPU/メモリ/電池/速度のBefore/Afterは未計測で、高速化を主張しない。
- OSS/ライセンス/課金/バックエンドは追加なし。設定最下部のライセンス表示と全文を維持する。

## 再現

```sh
MEMORA_COMPANY_PREVIEW_OUTPUT=<出力先> bash tools/checks/run-company-presentation-checks.sh --preview
bash tools/checks/run-artifact-operation-checks.sh --company-preview
bash tools/checks/run-quality-checks.sh --output-dir <未作成の結果先>
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
python3 -B tools/checks/prepare-company-quicklook.py <出力先> <未作成のコピー先>
qlmanage -t -s 960 -o <PNG先> <コピー先>/*-preview-only.pptx
swiftc -parse-as-library tools/checks/ComparePresentationRenders.swift -o <比較実行ファイル>
swiftc -parse-as-library tools/checks/ProbeCompanyPresentationColors.swift -o <色測定実行ファイル>
```

作業用データ/実行ファイルは外部SSDへ置く。
表示例: 設定 → 診断とプレビュー → 状態と復旧UI → 65レイアウト → 会社書式の追加ページ。
本番入口は保存済み会社スライドの詳細。表示例は個人データを保存/送信しない。
GitHub Actionsは[Host quality checks](https://github.com/Skyjoy0512/Memora-iOS/actions/workflows/quality.yml)で同じHEADを照合する。
