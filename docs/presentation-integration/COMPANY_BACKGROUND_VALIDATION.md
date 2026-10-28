# 会社プレビューの背景検査

2026-10-29。開始main: `b5f2c4c99690864213d488279826f836e0e4009d`。
会社マスター/レイアウトの背景を厳密に検査し、未対応の指定を黙って省略しないようにした。
UI・保存形式・資料内容・既存PPTXの書き出し方式は変更していない。最終完成数は **0 / 65**。

## 再現した問題と修正

白の`solidFill`の後に黒の`solidFill`がある背景を、旧readerは受け入れた。
新しい回帰検査を旧実装へ先に追加して、この受け入れを検出した。[失敗ログ](background-validation/checks/baseline.log)。
これはreaderでの再現で、旧PowerPointや旧PDFの見た目を実測した結果ではない。

- 背景は1つ、`bgPr`は1つ、その中は単色fill1つと任意の空`effectLst`1つだけに限定する。
- fillを先頭に要求し、重複したfill/effect、未知属性、空白以外のテキスト、未知namespaceを拒否する。
- 色は変換のない白の`srgbClr`または`schemeClr bg1`に限定する。従来のテーマ/白背景/コントラスト検査も維持する。
- 未対応の背景は型付きエラーでプレビュー作成を止める。省略したPDFは作らない。
- 会社PPTX内の元部品を修正したり、ユーザーの原本を上書きしたりしない。

[MicrosoftのbgPr説明](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.backgroundproperties?view=openxml-3.0.1)では、
背景には画像や効果等も含まれる。本修正はその全種類への対応ではなく、白背景の対応範囲を厳密に扱うための制限。
有効なOpen XMLでも、この描画subsetに含まれなければ拒否する。

## 回帰検査

- 対応5パターン×master/layout: readerと実際のpackageプレビュー10ケース成功。
  背景省略、白単色、任意の空effect、bg1、空白のある整形XML。
- 未対応/不正29パターン×master/layout: readerで58件を`unsupported`として拒否。
  実packageプレビューでも58件を拒否し、未知のエラーを成功扱いにしない。
- 65型の会社scene/PDFを再生成。日本語、3つの装飾画素、原本ページ除外、再生成一致を検査。
- 独立ZIP/XML検査65/65: 編集可能図形、関係先、元部品バイト、会社layoutとの関連を検査。
- b01/m04/b22のnative PNGは前フェーズとバイト一致。今回のb22を目視した。
  全レンダラーの全ページ目視検証ではない。

検査ソースは`tools/checks/CompanyPresentationBackgroundChecks.swift`。
既存の会社プレビューrunnerから呼び、`next-generation`とGitHub Actionsの通常検査にも入る。
検査のskip・無効化・CIの失敗伝播変更はしていない。

## 実行結果

| 検査 | 結果 / 境界 |
| --- | --- |
| 会社背景・色・65型プレビュー/PDF | [成功](background-validation/checks/preview.log)。上記10/58件と65型のscene・実PDF画素/文字・独立PPTX検査 |
| 標準65型 | [65/65成功](background-validation/checks/presentation.log)。型の構造・編集/再生成・日本語・出典・XML。実Officeの描画ではない |
| 資料修正の権限 | [成功](background-validation/checks/presentation-access.log)。production権限検査、SQLite、失効等。AI/設定はfixture |
| リンク / OSS / CI pipeline | [リンク](background-validation/checks/inline-links.log)、[同梱OSS22件](background-validation/checks/oss.log)、[失敗伝播4件](background-validation/checks/pipeline.log) 成功 |
| Debug iOS preview | [成功](background-validation/checks/debug.log)。BitrigのiOSプレビューを更新。既存警告11件 |
| Release iOS Simulator | [成功](background-validation/checks/release.log)。既存警告11件。iOS 27.1 SDK / deployment iOS 26 |
| 既存6スイート | [6/6成功、各exit 0](background-validation/checks/summary.json)。next-generation / design-refresh / background-summary / summary-reliability / composer-layout / optimization。各ログも同じフォルダへ保存 |

コマンド: `run-company-presentation-checks.sh --preview`、`run-presentation-checks.sh`、
`run-artifact-operation-checks.sh --presentation-revision`、`run-inline-link-checks.sh`、
`verify-oss-resources.py`、`test_ci_failure_propagation.py`、`run-quality-checks.py --output-dir <外部SSDの新規検証フォルダ>`（すべて`tools/checks/`）。
ビルド: `bitrig preview -platform iOS` / `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`。
CIの結果はこのローカル実行と区別し、該当commitのActions実ログで確認する。

架空の原本SHA256は`620086818b6fd4f571af431ff177d63b82553d6c0ed5d0b8856a173f3bd04c1f`。
[前フェーズの原本/成果物](COMPANY_DECORATION_COLOR.md#成果物ログ)と同じfixtureを使い、ファイルを重複同梱しない。

## 変更しない範囲・残件

- 録音・SQLite・backup・プレビュー失効gate・企業原本・PPTX部品保持を変更しない。
- 一般的な会社書式、背景画像/グラデーション、原本込みの会社PDFは未対応。
- 他の図形/色上書き等の全Open XML文法を、この背景検査だけで保証しない。
- [既知のQuick Look色差とPowerPoint自動操作のtimeout](COMPANY_DECORATION_COLOR.md)は解決していない。
  今回PowerPoint/Keynote/LibreOffice・実機・UI共有E2Eは実行していない。
- 65型のホスト検査成功は、元指示書の全完成条件65/65を意味しない。
