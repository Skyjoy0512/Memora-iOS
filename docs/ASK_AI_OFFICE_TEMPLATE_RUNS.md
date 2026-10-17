# 企業DOCX / PPTX: 分割された差し込み欄

基準コミット `602ebbe`。標準Swift/OOXMLエンジンを拡張し、Python/Nodeランタイム、サーバー、外部サービス、第三者コードをアプリへ追加していない。

## 対応した処理

Word/PowerPointでは文字列が複数のrun/text要素に分かれる場合がある。従来はその欄を検出すると利用不可にしていた。
今回、**同じ段落の通常の連続run**に限り、分割された `{{title}}` などをまとめて検出し、値を差し込めるようにした。

- `OfficeTemplateTextPart`: 名前空間を検証済みのXML treeと原本の文字範囲を対応させる。
  対象text要素の内容だけを置き換え、周辺XMLは再シリアライズしない。
- 値は欄の先頭の文字が属するrunへ入れる。ほかのrunからは欄の文字だけを取り除く。
  元のrun、文字/段落の書式、図形、配置、表などを削除・再構築しない。
  欄の前後の文字は元のrunに残す。必要なtext要素に `xml:space="preserve"` を追加/更新する。
- Wordは標準名称のdocument.xml/headerN.xml/footerN.xml、PowerPointはslideN.xmlが対象。
  マスター、レイアウト、テーマ、画像、ノートなどの非対象partは解凍後のbytesを保持する。
  ZIPコンテナは再構成するため圧縮バイト列全体の同一性を保証するものではない。
- 同じ段落でも改行、タブ、ブックマーク等の構造境界はまたがない。
  フィールド、リンク、変更履歴、content control、AlternateContent内の欄、text内のコメント/CDATA等は保守的に拒否する。
  コメントがrunの間にある場合はコメントを残して処理する。
- Transitional/StrictのWord/DrawingML名前空間、接頭辞の違い、数値文字参照、絵文字を含むUTF-16位置、
  繰り返し/隣接する欄、空の差し込み値に対応する。UTF-8のBOMとCR/CRLFを保持し、XMLで使えない制御文字は黙って削らず拒否する。明示的なUTF-8以外のencoding宣言は未対応。欄名は従来どおりASCII英字開始・英数字/underscore・40文字まで。
- 欄は30種類までとし、31種類以上は登録前の解析で拒否する。既存バックアップの欄数制限と合わせ、復元できない登録情報を新たに作らない。Wordの値は1欄10,000文字、PowerPointは120文字の制限を維持する。
  繰り返しによる文字列の増大を変更前に予約・検査し、XML part 2MiB、出力part合計8MiBを上限にする。
  文字あふれやOffice上の最終ページ数を保証する上限ではない。

## 登録済みテンプレート

解析情報へoptionalのengineVersionを追加。省略された旧データもdecodeでき、自動で登録内容を変更しない。
既存の会社テンプレート詳細に「テンプレートを再解析」を追加した。操作は端末内だけで実行する。
解析後に原本snapshot・workspace・workspace generation・復元/保護状態・キャンセルを再照合し、保存成功後だけmodelを更新する。
古い解析で不可とされたテンプレートも、この操作で対応範囲を再確認できる。ID、ファイル参照、書式バージョン、原本bytesは保持する。
保存失敗時は解析情報を差し替えない。workspace切替時には詳細の生成ファイル表示/プレビュー/入力も解除する。
再解析と生成それぞれの実処理を示す進行文言を使い、外部AIで自動生成しない。

## 検証

`bash tools/checks/run-artifact-checks.sh`。`MEMORA_KEEP_SPLIT_FIXTURES=1` 付きで実行すると、架空の生成結果2ファイルをdocs/fixturesへ保存する。

- Swiftの本番engineでDOCX/PPTXを実際に生成し、ZIP/XML/本文を再読み込みする。
- マーカーの各分割位置、書式保持、接頭辞/Strict名前空間、文字参照、絵文字、前後空白、空の値、隣接/繰り返しを検査。
- 段落・改行・タブ・変更履歴・フィールド・リンク・text内コメント、不完全な欄、生成サイズ超過を拒否する。
- Python標準ライブラリの独立検査で、同じ生成ファイルを再読込する。要素数・順序・書式属性と非対象partが保持されていることを照合する。
  Pythonコードは検証用の別プロセスであり、iOSに組み込まない。
- `CompanyTemplateAnalysisChecks` は本番の再解析extensionを使用し、旧形式更新、原本/ID/version保持、workspace/generation、
  途中編集/削除/許可範囲変更、復元/保護、キャンセル、SQLite再読込と書き込み失敗を検査する。
  stored state・ファイル参照の解決・persistNow入口はfixture、解析とLocalStoreの書き込みは本番コード。
- 実ユーザーのファイル/DB/APIキーは使用しない。

## 実ファイルと表示

- [生成DOCX](fixtures/ask-ai-artifacts/split-runs.docx)
- [生成PPTX](fixtures/ask-ai-artifacts/split-runs.pptx)
- [Mac Quick LookのDOCX先頭ページ](qa/askai2/office-template-runs/docx-quicklook.png)
- [Mac Quick LookのPPTX先頭スライド](qa/askai2/office-template-runs/pptx-quicklook.png)

Macの `qlmanage -t -s 1200` で両ファイルのthumbnail生成に成功し、日本語の差し込み値・見出し・本文/表を画像で確認した。
これはMac Quick Lookの先頭ページ/スライドの確認であり、Microsoft Officeの全ページ描画、実機Quick Look、実企業書式の高忠実度検証とは区別する。

## ビルドと回帰結果

- 最終コードの専用artifact/analysisテスト: 成功。
- 指定の `run-next-generation-checks.sh` / `run-motion-loading-checks.sh` / `run-optimization-checks.py`: すべて成功。
- `bitrig preview -platform iOS`: Debugビルド成功、プレビュー起動。
  最終ログ `2026-10-17T18-12-18-4e9ae6d5.log`。
- `bitrig build -destination 'generic/platform=iOS Simulator' -configuration Release`: 成功。
  最終ログ `2026-10-17T18-12-18-c88df5c0.log`。
- 両ビルドとも既存の警告11件、コンパイル/リンクエラーなし。実機性能値や全シナリオのE2E成功は主張しない。
- 生成例SHA-256: DOCX `1bee466887e02fb2d36e3791aed1bf1fda8f844bd94cee1632458ec9b81d854f`、
  PPTX `37a90687bf04b79eec02a6f5741c07c09832d2cf3cdfe2279fb0937d036eafc7`。

## 未対応・未検証

条件分岐/ループ/繰り返し行やスライドの追加、画像差し替え、グラフ更新、段落やフィールドをまたぐ置換、ノート/マスターへの差し込みは未対応。
複雑な会社書式、長文の自動改ページ/あふれ/フォント代替、Office上の編集/再保存は未検証。
生成ファイルは編集可能なOOXML文字要素を残しているが、あらゆるOffice構造の完全編集/完全再現を意味しない。
再解析ボタンを実利用者の登録テンプレートで操作するUI E2E、実機VoiceOver/性能も未検証。

## 設計確認に用いた一次資料

[Microsoft: WordのParagraph/Run/Text](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-open-and-add-text-to-a-word-processing-document)、
[Word Textとxml:space](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.text?view=openxml-3.0.1)、
[DrawingMLのParagraph](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.paragraph?view=openxml-3.0.1)。
コードは独自実装。これらの構造説明は既存会社資料の完全再現を保証するものではない。
