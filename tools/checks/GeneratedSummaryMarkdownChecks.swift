import Foundation

@main
enum GeneratedSummaryMarkdownChecks {
  static func main() {
    let samples: [(String, String)] = [
      ("# 題\n## 決定事項\nなし\n## 話題\n本文", "# 題\n## 話題\n本文"),
      ("## 親\n### 空\n記録なし\n## 残す\n問題なしと確認した", "## 残す\n問題なしと確認した"),
      ("## 表\n| 項目 | 値 |\n| --- | --- |\n| | |", ""),
      ("## 行動\n- [ ]", ""),
      ("---\n## 内容\n本文\n---\n---", "## 内容\n本文"),
      ("## 同じ\n事実\n## 同じ\n事実", "## 同じ\n事実"),
      ("## 引用\n> なし", "## 引用\n> なし"),
      ("## 状態\n担当者は未定と合意した", "## 状態\n担当者は未定と合意した"),
      ("## コード\n```text\n## 空\nなし\n```", "## コード\n```text\n## 空\nなし\n```"),
      ("## 内容\n本文\n<memora-data>\n{\"actions\":", "## 内容\n本文")
    ]
    for (source, expected) in samples {
      let result = SummaryResponseParser.generatedMarkdown(source)
      precondition(result == expected, "\(source) => \(result), expected \(expected)")
      precondition(SummaryResponseParser.generatedMarkdown(result) == result)
    }
    let different = "## 同じ\nA\n## 同じ\nB"
    precondition(SummaryResponseParser.generatedMarkdown(different) == different)
    let table = "## 比較\n| 案 | 条件 |\n| --- | --- |\n| A | 承認後 |"
    precondition(SummaryResponseParser.generatedMarkdown(table) == table)
    print("GeneratedSummaryMarkdownChecks: passed (10 cleanup/preservation cases, distinct headings, nonempty table, idempotence)")
  }
}
