# Officeソースの端末内抽出

対象はDOCX / PPTX / XLSXのOpen XMLパッケージ。元ファイルのコピー・指紋・
SQLite保存を変えず、既存`ProjectSourceExtraction`から呼び出す。Ask AIの添付も
同じ抽出経路を使う。準備済み添付のidentity確認・8,000文字上限・未信頼資料の
扱い・送信前の許可・操作承認は従来どおり。本文の取得は外部送信の同意ではない。

## 読み取るもの

| 形式 | 読み取る文字 | 対応しないもの |
| --- | --- | --- |
| DOCX | 本文・表内の段落、改行・タブ。削除/moveFromの内容を除外 | 画像、ヘッダー、脚注、コメント、番号/レイアウト再現 |
| PPTX | presentationのrelationshipが指定するスライド順、DrawingMLの段落。スライド番号を本文に付記 | 画像、グラフ、埋込資料、発表者ノート、配置順の視覚的推定 |
| XLSX | workbookのシート順、セル番地、共有/inline文字列、数値、真偽値、保存済みの数式結果。シート名と同行の値を同じ本文ブロックに保持 | 数式実行、外部リンク更新、日付/表示形式変換、画像/グラフ。非表示シートは除外するが非表示行/列を含み得る |

表示・画像を含むファイル全体を理解したとは扱わず、本文取得に成功しても
`textCoverage.partial`（一部をAI参照可）を保存する。空のファイルは内容未取得。
古いDOC / PPT / XLS、マクロ拡張子、UTF-16 XML、暗号化、ZIP64、対応外の
圧縮・複雑な構成は成功と表示しない。PDF/テキストへの書き出しを案内する。
以前保存した未解析Officeは、詳細の「解析を再試行」から明示的に解析できる。

## 上限と安全境界

- アーカイブ50MiB、2,048エントリー、宣言された展開合計128MiB。
- 選択したXMLは1パート2MiB、読み取り合計8MiB。本文80,000文字・UTF-8 256KiB・2,000ブロック、
  50スライド、20シート、5,000セルの上限。先に達した上限で文字出力を止める。
  JSONのescapeとmetadataを含めても既存TextReaderの2MiB以内に収める。
- XMLは深さ48・30,000ノードまで。UTF-8のみ、DTD/ENTITY宣言を拒否し、
  XMLParserの外部entity解決を無効化する。JavaScript・HTML・スクリプトは実行しない。
- ZIPはstore/DEFLATEのみ。中央directoryとlocal header、サイズ、descriptor、
  重複名、範囲の重なり、CRCを検査。絶対パス、上位参照、symlinkを拒否する。
  パッケージ内の名前でファイルを書き出すことはない。
- relationshipsは実在するパッケージ内のパートへだけ解決する。外部参照は取得しない。
  上位参照はpackage root内に正規化できる場合だけ認め、URL/percent encodingを拒否する。
- 通常経路は既存のsecurity scope・regular-file/symlink・ファイル容量の検査後に
  utility workerで解析。entry/XML/出力の間でキャンセル確認する。
- 不正なパートを途中まで正常扱いして保存しない。解析失敗は元コピーを保持し、
  再試行に外部操作の再送を含めない。privacyとscopeの判定は抽出器から独立している。

## 再利用と依存

既存のZipArchive writer/CRC、PPTXWriter、ProjectSourceFiles/TextReader、
ProjectSourceExtraction、AIAttachmentText、projectの索引/引用/承認を利用する。
ZIP reader、bounded XML reader、Officeの形式別変換だけを追加した。
外部ライブラリ・バックエンド・契約・識別子/App Group変更は追加していない。
AppleのCompressionとFoundation XMLParserを使用する。

仕様確認: [Apple COMPRESSION_ZLIB](https://developer.apple.com/documentation/compression/compression_zlib)、
[Microsoft WordprocessingML](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-open-and-add-text-to-a-word-processing-document)、
[PresentationML](https://learn.microsoft.com/en-us/office/open-xml/presentation/structure-of-a-presentationml-document)、
[共有文字列](https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/working-with-the-shared-string-table)。
SDKのコードは取り込まず、構造の確認にのみ参照した。

## 検証経路

`tools/checks/run-next-generation-checks.sh`はPython標準zipfileで一時的なfixtureを
生成し、実Swift readerを呼ぶ。store/DEFLATE/descriptor、順序、日本語、CRC、
不正ZIP/XML、外部参照、上限、キャンセルを検証する。ユーザー資料・通信は使わない。
DEBUG自己チェックは既存のMemora PPTX exportも読み戻す。

設定 › プロトタイプ › 状態と復旧UI › Officeソース（取込と保存の検証）は、
新規の検証用プロジェクトへ3形式を通常と同じimport経路で取り込み、本文・添付・
SQLiteの再読込を照合する。元のファイル一覧は使わず、作成IDだけで後始末する。
検証プロジェクトに別の内容が追加された場合はそのプロジェクトを削除しない。
この導線とfixtureはDEBUG限定。実LLM/実Office製品で作成した広い資料群/実機性能の
検証を代替しない。buildとSimulatorの最新結果は[品質改善記録](QUALITY_IMPROVEMENT.md)。
