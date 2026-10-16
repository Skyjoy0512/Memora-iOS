# 架空データの生成検証ファイル

- generated.docx: Swift DOCXWriter + CompanyTemplateEngineが生成。日本語、見出し、編集可能な段落と表。
- generated.pptx: 既存PPTXWriter + CompanyTemplateEngineが生成。テキストボックス、元のmaster/theme/layoutを保持。
- long.docx: 300段落のフロー文書。実Officeでのページ数は未検証。
- poc.docx / poc.pptx: 独立Python差分PoCの結果。未変更partは同一bytes。

実ユーザー記録・実会社の書式・ブランドロゴ・API出力は含みません。ZIP/CRC/XML/再読込を検証していますが、Officeでの最終レイアウト・フォント代替・文字あふれは未検証です。アプリには同梱しません。
