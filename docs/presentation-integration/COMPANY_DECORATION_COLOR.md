# 会社書式の装飾色・明度変換

2026-10-29。開始main: `c5374bbdc700c9ca5c43a07edec10972663e8a16`。
会社マスター/レイアウトにある単色矩形・楕円装飾の`lumMod`/`lumOff`を、追加ページの共通scene/PDFへ反映した。
原本・PPTXのマスター/レイアウト部品を変換後hexへ書き換えない。UI/保存形式/会社書式の選択条件も維持する。
これは会社PDF全体やOffice完全互換の完成ではない。最終完成数は **0 / 65** のまま。

## 実装完了

- 装飾の`srgbClr`と、確定できる会社テーマの`schemeClr`を入力にする。
- `lumMod`はHSL明度の乗算、`lumOff`は加算として、XMLの順序を保持する。各ステップで0〜1へ制限し、最後にだけ8bit RGBへ量子化する。
- 対応範囲は0〜100000のASCII整数表現、最大4ステップ。これは意図的なsubsetで、規格上の全値域・全表記への対応ではない。
- 透明度、shade/tint/gamma、未知の変換、範囲外、%/小数/符号付き表記、子要素/未知属性/不明namespace/文字混入等は、黙って除外せず拒否する。
- 既存の生成色用HSL helperも再利用し、NaN/Infinity等が整数変換のクラッシュへ進まないよう入力範囲を検査する。
- 原本のPPTX生成・保存は従来どおり。出力PPTXには会社側の変換XMLをそのまま残す。

[MicrosoftのlumMod](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.luminancemodulation?view=openxml-3.0.1) /
[lumOff](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.luminanceoffset?view=openxml-3.0.1)の説明を確認した。
[Office互換性注記](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/fa8c6409-ddd0-46bd-b995-0b00342d9aeb)もあるため、
仕様ベースの算出と以下の実描画を、PowerPointの全バージョンでの一致保証に読み替えない。

## 検証

| 検査 | 結果/境界 |
| --- | --- |
| 既知色 | 12件成功。テーマ/direct色、順序差、各段clamp、中間RGB丸め防止、0/100%端点、4段上限 |
| 未対応/不正XML | 29件を型付きunsupportedで拒否 |
| 数値入力 | 内部helperのNaN/Infinity/負値/上限超過8件を拒否 |
| 全65型scene/PDF | 全型でマスター暗色・レイアウト明色を保持。PDFをsRGB bitmapへ実描画し、3点の画素値、日本語/原本除外/再生成一致を検査 |
| 独立PPTX検査 | 65/65。XML/関係/編集可能図形/日本語/出典/元部品バイト/会社layout参照 |
| 集約成果物 | PDFは追加65ページのみ。PPTXは原本1＋追加65ページ |
| 実画像目視 | b01/m04/b22のnative PDF画像と、b22のQuick Look画像を確認。全65型の全レンダラー目視ではない |
| Debug / Release | 両方成功、各11件の既存警告。iOS 27.1 SDK、deployment iOS 26、Simulator対象 |
| 既存6スイート | 6/6 Pass。今回の色検査と65型検査、前フェーズの結果待ち12ケースもnext-generationで成功 |

fixtureの原本SHA256: `620086818b6fd4f571af431ff177d63b82553d6c0ed5d0b8856a173f3bd04c1f`。
実在企業の書式・ロゴ・業績ではなく、テスト用の単色矩形3つと架空データ。

## 成果物・ログ

- [架空の原本](decoration-color/source.pptx) / [原本＋追加65ページPPTX](decoration-color/corporate-catalog.pptx) / [追加65ページだけのPDF](decoration-color/corporate-additions-65.pdf)
- [b22 PDF](decoration-color/b22.pdf) / [Quick Look画像](decoration-color/quicklook-b22.png)
- native PDF描画: [b01](decoration-color/native/b01.png) / [m04](decoration-color/native/m04.png) / [b22](decoration-color/native/b22.png)
- [個別色/65型/独立PPTX検査](decoration-color/checks/preview-checks.log) / [Debug](decoration-color/checks/debug.log) / [Release](decoration-color/checks/release.log)
- [6スイート結果](decoration-color/checks/summary.json)と同フォルダの6ログ

変更ソース: `App/CompanyPresentationColor.swift`、`App/CompanyPresentationDecorationReader.swift`。
検査: `CompanyPresentationColorChecks.swift`、`CompanyPresentationPreviewChecks.swift`、
`ProbeCompanyPresentationColors.swift`、`run-company-presentation-checks.sh`（いずれも`tools/checks/`）。
その他はこのレポート、総合レポート/バックログへの追補、架空fixtureと検査ログ。

## 実描画の差を残す

b22を960×540の明示的sRGB CGContextへ描画し、同じ座標を測定した。

| 対象 | native PDF | Quick Look PPTX |
| --- | --- | --- |
| 未変換マスター矩形 (850,10) | 0,90,80 | 0,90,80 |
| マスターlumMod=50000 (730,10) | 0,45,40 | 0,45,39 |
| layout lumMod=20000, lumOff=80000 (610,10) | 171,255,246 | 171,255,245 |
| 緑の円 (267,300) | 0,90,80 | 0,108,99 |
| 茶の円 (693,300) | 128,51,0 | 148,68,0 |

新規の明度装飾にも1階調の差があり、既存の円の色差も残る。原因を丸めやQuick Lookだけに断定しない。
全形状の最終描画一致を合格にしない。[生測定](decoration-color/color-comparison.json)。
Quick Look用コピーは、原本ページのpresentation-list entryだけを検証用に除外したもの。
追加ページ/マスター/レイアウト/テーマは同じ部品。納品用fixture PPTXは原本込みのまま。

## 未実装・未検証

### ローカルPowerPointの確認は失敗

`/Applications/Microsoft PowerPoint.app` 16.114.1があり、既存の自動操作経路でversion取得は成功した。
架空66ページPPTXの外部SSD上の別コピーだけを開き、PDFへ保存する検査を試みたが、open操作が
45秒でAppleEvent timeout (-1712)となり、PDFは生成されなかった。
対象名に限定した後続照会は0資料。LaunchServices経由の通常openはexit 0だったが、
5秒後の同じ限定照会も0だった。コマンド受付を正常描画と扱わない。

原因は未特定。破損PPTX、ライセンス、ダイアログ、アクセス権等のどれかに断定しない。
コピーと生成済みPPTXのSHA256は両方`c71c02e237decb913facc494134c018813d2d2427089b557226632451f6cfba8`のまま。
利用者の文書、契約、認証、設定は変更せず、既存資料やアプリ全体をclose/quitしていない。
Keynote/LibreOfficeは標準のApplications配置とPATHで見つからなかった。他の配置の存在までは否定しない。

[version](decoration-color/checks/powerpoint-access.log) /
[失敗](decoration-color/checks/powerpoint-export.log) /
[限定照会](decoration-color/checks/powerpoint-fixture-check.log) /
[通常open後の照会](decoration-color/checks/powerpoint-fixture-check-launchservices.log) /
[原本/コピーのハッシュ](decoration-color/checks/powerpoint-source-hashes.log)。
PowerPointの画面目視・描画・編集成功は今回も未検証。

### 残る範囲

画像ロゴ、輪郭線、複雑な図形、任意色変換、一般プレースホルダー/寸法、原本込み会社PDFは従来どおり未対応。
Office/Keynote/実機、今回の明度装飾を使った実資料UI→共有E2E、全型の実AI生成/修正、最終画像一致は未検証。
新規UIはなくSimulator Before/Afterを作っていない。ビルド/プレビュー更新を、新機能の実機E2Eと扱わない。
性能のBefore/Afterは未計測で、高速化を主張しない。

新規依存/サービス/API呼出/固定費/Project.json変更なし。
録音、文字起こし、ジャーナル、保存形式/バックアップ、権限・取消・workspace検査、BYOK、認証/購入は維持する。

## 再現

```sh
MEMORA_COMPANY_PREVIEW_OUTPUT=<未作成の外部SSD結果先> bash tools/checks/run-company-presentation-checks.sh --preview
bash tools/checks/run-quality-checks.sh --output-dir <未作成の外部SSDログ先>
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
python3 -B tools/checks/prepare-company-quicklook.py <結果先> <未作成のコピー先>
qlmanage -t -s 960 -o <PNG先> <コピー先>/b22-preview-only.pptx
swiftc -parse-as-library tools/checks/ProbeCompanyPresentationColors.swift -o <測定ツール>
```

色の個別検査は既存next-generation内の65型プレビュー検査から実行される。スイートの削除/skipはしていない。
