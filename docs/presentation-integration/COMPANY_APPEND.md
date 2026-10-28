# 会社PowerPointへの構造化ページ追加

2026-10-28。開始main: `40dbce5ccc9a5d5b42f34c5b99f26d2e25cf4792`。
前フェーズの計測情報から、**対応条件内の原本へ65型を追加するローカルexport経路**を実装した。
一般の会社書式を再現できるという報告ではない。全完成条件は引き続き **0 / 65**。

追補: [編集後の確認付き再出力とファイル履歴](COMPANY_REEXPORT.md)を追加した。
下記のUI未接続はこのフェーズ時点の記録。現在は対応する構造化会社資料の詳細へ再出力を接続済み。
一般書式や会社PDFの未達は変わらない。

## 実装した範囲

- `CompanyPresentationExporter`は原本を読み取り、既存ページを残した別PPTXへ構造化スライドを追加する。会社の実在するレイアウト・マスター・テーマを参照し、新しいMemoraマスターで置換しない。
- 元のページ、マスター、レイアウト、テーマ、メディア、既存ノート等は展開後の部品バイトを保持する。変更する既存部品はpresentation・そのrelationships・content typesの3点と、存在する場合のappプロパティのページ数だけ。ZIP圧縮方法そのものの一致は保証しない。原本ファイルは書き換えない。
- 新規ページは文字・矩形・円・多角形・線の編集可能オブジェクト。会社テーマの色役割と見出し/本文の和文・欧文フォントを使う。ヒートマップ等の淡色は会社accentの明度変換で区別する。Memoraの青・オレンジを固定値で上書きしない。
- 会社フォントをCoreTextで再計測し、文字あふれとマスター/レイアウト装飾との衝突を拒否する。テーマ色のコントラスト、実在フォント、部品数・容量、リレーション・ID・寸法を検査する。非対応時は標準テーマへ黙ってフォールバックしない。
- speaker notesに注記・構造化内容・数値・出典を保持。既存notes masterを再利用するか、会社テーマに関連付けたnotes masterを新設する。原本中の未使用relationships部品との名前衝突も避ける。
- `create_slides`へ`template_mode=append`を追加。利用者が選んだ会社テンプレートを、既存の承認経路で処理する。従来の`{{name}}`差し込みは`markers`（省略時の既定）のまま維持する。append時の`template_fields`は空にする。
- @テンプレートの利用可否とagentへの指示へ接続。AIへ渡すのはID・形式・欄名・追加候補の有無であり、会社ファイル・テーマ・ロゴ自体は端末から送信しない。実AIによるツール選択のE2Eは未実施。
- 文書へoptionalの`companyTemplateVersion`を保存し、旧文書を読めるまま、編集・再出力・SQLite・バックアップで原本との関係を保持する。不正な版番号や、会社文書のテンプレート指定が失われた再出力を拒否する。
- 保存前後にworkspace世代、元テンプレートの一致、キャンセル、復元、保護状態を確認する。失効した処理の出力を確定しない。追加のAPI・サーバー・依存ライブラリ・固定費はない。

Presentations skillの原本/マスター保持と実出力確認の方針を、iOSの既存Swift実装に適用した。Python・Node・ブラウザをアプリへ同梱していない。参考OSSのMIT全文・著作権・設定のライセンス表示は維持しており、新しい他社ブランドは追加していない。

## 現在の対応条件と制限

1. 960×540pt（12192000×6858000 EMU）のTransitional PPTX。canonicalな`ppt/`配下の関連付けに限定する。原本1ページ以上、新規1〜65ページ、合計500ページ以下。ZIPは既存の容量/パート上限内に限る。
2. マスターとレイアウトにプレースホルダーがなく、位置を確定できる空白レイアウトが必要。白背景、読み取れる会社テーマ、端末で計測できるフォント、衝突しない装飾が必要。画像/グラデーション背景、回転・反転・グループ、個別themeOverride、変換付きテーマ色の未解決分は採用しない。
3. `{{name}}`や不完全な差し込み欄が残るPPTXはappendに使わない。既存の別経路で差し込む。署名・マクロ・埋め込みExcel・外部参照を拒否する既存方針は緩めない。上流SuperTemplateの埋め込み拒否は引き続き未解決。
4. 一般的な会社のタイトル/本文プレースホルダーへの配置、任意寸法への拡縮、会社の表/グラフ詳細書式、ページ番号/フッター新規生成は未実装。今回の制限は保守的であり、Officeで有効なテンプレートでも拒否する場合がある。
5. **会社書式のネイティブプレビューとPDF出力は未実装**。構造化編集画面は新規内容の標準表示であり、会社のマスターを描画しない。PPTXの会社書式を見る経路とは異なる。資料一覧の枚数は新規内容の枚数で、成果物の原本ページ込み枚数ではない。
6. 会社PPTXへ追加するAskAI経路は接続済みだが、保存済み会社資料の編集後に同じ画面から再出力する操作や、会社資料のAI部分修正UIは未接続。内部の再生成経路のテストを、UI完成とは扱わない。編集前の成果物は保持し、既存の「編集前」表示を維持する。
7. 図表は編集可能なPowerPoint図形であり、Office Chartや埋め込みExcelのデータ編集機能ではない。フォント計測は今回の日本語・ASCII fixtureで確認した範囲。実会社データの全言語・全フォント・全装飾を検証済みとはしない。

## 検証と成果物

対象は架空データと合成テンプレートのみ。上流の暖色テーマや他社ロゴを使わず、独自の緑/茶の会社テーマと右上の矩形装飾で、Memora標準色からの分離を検証した。矩形は実ロゴ画像ではない。

| 検査 | 結果の境界 |
| --- | --- |
| b01–b30 / m01–m35の追加export | 65/65。各原本1枚＋新規1枚、全型まとめて原本1枚＋新規65枚 |
| 独立ZIP/XML検査 | 65/65。部品の参照先、content types、重複ID、文字/図形、日本語、出典、元部品バイトの保持 |
| 再生成 | 同じ入力のPPTXはバイト一致。編集後は原本から再生成し、前回成果物へ重複追加しない |
| 保存ライフサイクル | production prepare/save/editと実SQLite再読込。テンプレート版7、原本・旧成果物保持、不正mode/ID/fields、保護/復元の拒否 |
| バックアップ | optional版番号の復元と不正な版番号/ID組合せの拒否。旧版互換を既存検査と併走 |
| Quick Look | 65型の追加ページ画像を生成、5枚の比較シートを目視。原本込み66ページのHTMLプレビューも生成 |
| 既存6スイート | 全Pass。next-generation / design-refresh / background-summary / summary-reliability / composer-layout / optimization。追加候補判定の最終修正後は65型専用検査とAskAIシナリオも再実行 |
| Debug / Release | 最終Swiftコードで両方成功。iOS Simulator向け、既存11警告。DebugはBitrigプレビューを更新 |
| 会社書式PDF/Office編集/実機 | 未検証。ネイティブ会社PDFは未実装。Quick Lookの成功で置き換えない |

- [原本fixture](company-append/source.pptx)、[原本＋65型の成果物](company-append/corporate-catalog.pptx)
- [独立パッケージ検査](company-append/checks/package-validation.json)、[個別65型ログ](company-append/checks/company-layouts.log)
- [6スイート結果](company-append/checks/summary.json)、[Debug/Release結果](company-append/checks/builds.json)、[実描画の境界とハッシュ](company-append/checks/quicklook-validation.json)
- Quick Look比較: [b01–b15](company-append/renders/sheet-1.png)、[b16–b30](company-append/renders/sheet-2.png)、[m01–m15](company-append/renders/sheet-3.png)、[m16–m30](company-append/renders/sheet-4.png)、[m31–m35](company-append/renders/sheet-5.png)

Quick Lookのthumbnailは先頭ページしか描画しないため、検証用コピーでpresentationの一覧から原本ページだけを除外した。追加ページの文字・図形・レイアウト・マスター・テーマは実成果物と同じバイト。**このコピーは納品用PPTXではなく、元の原本込み成果物の全ページ描画検査とも異なる**。`prepare-company-quicklook.py`に処理を残した。ブラウザ経由の表示確認は実行環境の接続エラーで実施できず、Quick Lookの実PNGを確認した。

ビルド、既存6スイート、標準65型の最終結果は[チェックログ](company-append/checks/)に保存する。GitHub Actionsは同じHEADの[Host quality checks](https://github.com/Skyjoy0512/Memora-iOS/actions/workflows/quality.yml)で照合する。XCTest/XCUITestターゲット追加や実機・電池・性能Before/Afterは今回行っていない。性能改善を主張しない。

最初のホスト検査ではテストモデルのworkspace世代定義とBash 3.2の空配列展開を修正した。また、検査途中のソース変更をコンパイラが拒否したため、コード確定後に既存6スイートを再実行した。失敗を成功へ読み替えたり、テストをskipしたりしていない。

コードコミットは`38d37b7`、差し込みテンプレートを追加候補から分離する修正は`ba0c6d1`。
参考OSSのHEADは2026-10-28に再照合し、引き続き`e5f35e57e14d3998249a559c620a9286c95b4595`。

## 再現コマンド

```sh
MEMORA_COMPANY_APPEND_OUTPUT=<外部SSD上の出力先> bash tools/checks/run-company-presentation-checks.sh
bash tools/checks/run-artifact-operation-checks.sh
bash tools/checks/run-artifact-operation-checks.sh --presentation-revision
bash tools/checks/run-quality-checks.sh --output-dir <未作成の外部SSD上の結果先>
bash tools/checks/run-presentation-checks.sh
bitrig preview -platform iOS
bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release
python3 -B tools/checks/prepare-company-quicklook.py <出力先> <未作成の検証用コピー先>
qlmanage -t -s 960 -o <PNG先> <検証用コピー先>/*-preview-only.pptx
```

次はプレースホルダーを持つ一般会社書式への対応、会社書式のpreview/PDF一致、編集後の確認付き再出力UI、実AI・Office・実機の検証を進める。総合開発指示書全体の完了ではない。
